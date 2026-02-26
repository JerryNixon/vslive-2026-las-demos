// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

var builder = DistributedApplication.CreateBuilder(args);

var options = new
{
    CatalogDb = "CatalogDb",
    InventoryDb = "InventoryDb",
    DabConfig = new FileInfo(Path.Combine("..", "data-api", "dab-config.json")),
    DabCatalogConfig = new FileInfo(Path.Combine("..", "data-api", "dab-config-catalog.json")),
    DabInventoryConfig = new FileInfo(Path.Combine("..", "data-api", "dab-config-inventory.json")),
    DabImage = "1.7.83-rc",
    SqlCmdrImage = "latest"
};

// SQL Server

var sqlPassword = builder.AddParameter("sql-password", secret: true);

var sqlServer = builder
    .AddSqlServer("sql-server", password: sqlPassword, port: 1234)
    .WithDataVolume("sql-data")
    .WithLifetime(ContainerLifetime.Persistent);

// CatalogDb with SQL Commander

var catalogDb = sqlServer
    .AddDatabase(options.CatalogDb)
    .AddSqlCommander(hostPort: 2345);

var catalogSqlproj = builder.AddSqlProject<Projects.CatalogDb>("sqlproj-" + catalogDb.Resource.Name)
    .WithSkipWhenDeployed()
    .WithReference(catalogDb);

// InventoryDb with SQL Commander

var inventoryDb = sqlServer
    .AddDatabase(options.InventoryDb)
    .AddSqlCommander(hostPort: 3456);

var inventorySqlproj = builder.AddSqlProject<Projects.InventoryDb>("sqlproj-" + inventoryDb.Resource.Name)
    .WithSkipWhenDeployed()
    .WithReference(inventoryDb);

// Data API Builder with MCP Inspector

var dabServer = builder
    .AddDataAPIBuilder("data-api")
    .WithConfigFile(options.DabConfig, options.DabCatalogConfig, options.DabInventoryConfig)
    .WithImageTag(options.DabImage)
    .WithHttpEndpoint(port: 4567, targetPort: 5000, name: "http")
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
    .WithHttpEndpoint(port: 5678, targetPort: 6274, name: "http")
    .WithEnvironment("DANGEROUSLY_OMIT_AUTH", "true")
    .WithEnvironment("NODE_TLS_REJECT_UNAUTHORIZED", "0")
    .WaitFor(dabServer)
    .WithUrls(context => context.Urls.First().DisplayText = "Inspector");

await builder.Build().RunAsync();

static class Extensions
{
    public static IResourceBuilder<SqlServerDatabaseResource> AddSqlCommander(this IResourceBuilder<SqlServerDatabaseResource> db, string? name = null, string? imageTag = null, int? hostPort = null)
    {
        ArgumentNullException.ThrowIfNull(db);

        var commander = db.ApplicationBuilder
            .AddContainer(name ?? "sqlcmdr-" + db.Resource.Name, "jerrynixon/sql-commander", imageTag ?? "latest")
            .WithImageRegistry("docker.io")
            .WithHttpEndpoint(port: hostPort, targetPort: 8080, name: "http")
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