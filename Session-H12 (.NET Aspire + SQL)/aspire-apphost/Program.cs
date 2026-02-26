// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

var builder = DistributedApplication.CreateBuilder(args);

var options = new
{
    CatalogDb = "CatalogDb",
    InventoryDb = "InventoryDb",
    DabConfig = Path.Combine("..", "data-api", "dab-config.json"),
    DabCatalogConfig = Path.Combine("..", "data-api", "dab-config-catalog.json"),
    DabInventoryConfig = Path.Combine("..", "data-api", "dab-config-inventory.json"),
    DabImage = "1.7.83-rc",
    SqlCmdrImage = "latest"
};

// SQL Server

var sqlPassword = builder.AddParameter("sql-password", secret: true);

var sqlServer = builder
    .AddSqlServer("sql-server", password: sqlPassword)
    .WithDataVolume("sql-data")
    .WithLifetime(ContainerLifetime.Persistent);

var catalogDb = sqlServer
    .AddDatabase(options.CatalogDb)
    .AddSqlCommander();

var catalogSqlproj = builder.AddSqlProject<Projects.CatalogDb>("catalog-sqlproj")
    .WithSkipWhenDeployed()
    .WithReference(catalogDb);

var inventoryDb = sqlServer
    .AddDatabase(options.InventoryDb)
    .AddSqlCommander();

var inventorySqlproj = builder.AddSqlProject<Projects.InventoryDb>("inventory-sqlproj")
    .WithSkipWhenDeployed()
    .WithReference(inventoryDb);

var dabConfig1 = new FileInfo(options.DabConfig);
var dabConfig2 = new FileInfo(options.DabCatalogConfig);
var dabConfig3 = new FileInfo(options.DabInventoryConfig);

var dabServer = builder
    .AddDataAPIBuilder("data-api")
    .WithConfigFile(dabConfig1, dabConfig2, dabConfig3)
    .WithImageTag(options.DabImage)
    .WithEnvironment("CATALOG_CONNECTION_STRING", catalogDb)
    .WithEnvironment("INVENTORY_CONNECTION_STRING", inventoryDb)
    .WaitForCompletion(catalogSqlproj)
    .WaitForCompletion(inventorySqlproj);

var mcpInspector = builder
    .AddMcpInspector("mcp-inspector", options =>
    {
        options.InspectorVersion = "0.20.0";
    })
    .WithMcpServer(dabServer, transportType: McpTransportType.StreamableHttp)
    .WithParentRelationship(dabServer)
    .WithEnvironment("DANGEROUSLY_OMIT_AUTH", "true")
    .WithEnvironment("NODE_TLS_REJECT_UNAUTHORIZED", "0")
    .WaitFor(dabServer)
    .WithUrls(context => context.Urls.First().DisplayText = "Inspector");

await builder.Build().RunAsync();

static class Extensions
{
    public static IResourceBuilder<SqlServerDatabaseResource> AddSqlCommander(this IResourceBuilder<SqlServerDatabaseResource> db, string? name = null, string? imageTag = null)
    {
        ArgumentNullException.ThrowIfNull(db);

        var commander = db.ApplicationBuilder
            .AddContainer(name ?? "sql-commander-" + db.Resource.Name, "jerrynixon/sql-commander", imageTag ?? "latest")
            .WithImageRegistry("docker.io")
            .WithHttpEndpoint(targetPort: 8080, name: "http")
            .WithEnvironment("ConnectionStrings__db", db)
            .WithUrls(context =>
            {
                context.Urls.Clear();
                context.Urls.Add(new() { Url = "/", DisplayText = db.Resource.Name, Endpoint = context.GetEndpoint("http") });
            })
            .WithHttpHealthCheck("/health")
            .WithParentRelationship(db);

        return db;
    }
}