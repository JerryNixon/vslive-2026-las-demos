// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

var builder = DistributedApplication.CreateBuilder(args);

var options = new
{
    SqlServer = new
    {
        CatalogDb = "CatalogDb",
        InventoryDb = "InventoryDb",
    },
    DataApiBuilder = new
    {
        ConfigHead = new FileInfo(Path.Combine("..", "data-api", "dab-config.json")),
        ConfigCatalog = new FileInfo(Path.Combine("..", "data-api", "dab-config-catalog.json")),
        ConfigInventory = new FileInfo(Path.Combine("..", "data-api", "dab-config-inventory.json")),
        ImageTag = "1.7.83-rc",
    },
    Foundry = new
    {
        Endpoint = builder.Configuration["Foundry:Endpoint"] ?? throw new InvalidOperationException("Foundry:Endpoint is not configured in appsettings."),
        Deployment = builder.Configuration["Foundry:Deployment"] ?? throw new InvalidOperationException("Foundry:Deployment is not configured in appsettings."),
        Key = builder.Configuration["Foundry:Key"] ?? throw new InvalidOperationException("Foundry:Key is not configured in appsettings.")
    }
};

var sqlPassword = builder.AddParameter("sql-password", secret: true);

var sqlServer = builder
    .AddSqlServer("sql-server", password: sqlPassword, port: 8001)
    .WithDataVolume("sql-data")
    .WithLifetime(ContainerLifetime.Persistent);

// CatalogDb with SQL Commander

var catalogDb = sqlServer
    .AddDatabase(options.SqlServer.CatalogDb)
    .AddSqlCommander(externalPort: 8002);

var catalogSqlproj = builder.AddSqlProject<Projects.CatalogDb>("sqlproj-" + catalogDb.Resource.Name)
    .WithSkipWhenDeployed()
    .WithReference(catalogDb);

// InventoryDb with SQL Commander

var inventoryDb = sqlServer
    .AddDatabase(options.SqlServer.InventoryDb)
    .AddSqlCommander(externalPort: 8003);

var inventorySqlproj = builder.AddSqlProject<Projects.InventoryDb>("sqlproj-" + inventoryDb.Resource.Name)
    .WithSkipWhenDeployed()
    .WithReference(inventoryDb);

// Data API Builder with MCP Inspector

var dabServer = builder
    .AddDataAPIBuilder("data-api", 8004).WithIconName("Drag")
    .WithConfigFile(options.DataApiBuilder.ConfigHead, options.DataApiBuilder.ConfigCatalog, options.DataApiBuilder.ConfigInventory)
    .WithImageTag(options.DataApiBuilder.ImageTag)
    .WithEnvironment("CATALOG_CONNECTION_STRING", catalogDb)
    .WithEnvironment("INVENTORY_CONNECTION_STRING", inventoryDb)
    .WaitForCompletion(catalogSqlproj)
    .WaitForCompletion(inventorySqlproj);

// Web Apps

builder.AddWebClient("web-app-aspnet", 8006, 8080, dabServer, "ASPNET")
    .WithReference(dabServer);

builder.AddWebClient("web-app-react", 8007, 3000, dabServer, "React", configure: client =>
{
    client.WithEnvironment("NODE_TLS_REJECT_UNAUTHORIZED", "0");
}).WithReference(dabServer);

builder.AddWebClient("web-app-python", 8008, 3000, dabServer, "Python")
    .WithReference(dabServer);

builder.AddWebClient("web-app-java", 8009, 3000, dabServer, "Java")
    .WithReference(dabServer);

// MCP Inspector

var mcpInspector = builder
    .AddMcpInspector("mcp-inspector", o =>
    {
        o.InspectorVersion = "0.20.0";
    }).WithIconName("EyeTracking")
    .WithMcpServer(dabServer, transportType: McpTransportType.StreamableHttp)
    .WithParentRelationship(dabServer)
    .WithHttpEndpoint(port: 8005, targetPort: 6274, name: "http")
    .WithEnvironment("DANGEROUSLY_OMIT_AUTH", "true")
    .WithEnvironment("NODE_TLS_REJECT_UNAUTHORIZED", "0")
    .WaitFor(dabServer)
    .WithUrls(context =>
    {
        context.Urls.First().DisplayText = "Inspector";
        context.Urls.RemoveRange(1, context.Urls.Count - 1);
    });

// Web Chat (AI + MCP)

builder.AddProject<Projects.WebChat>("web-chat")
    .WithIconName("Chat")
    .WithHttpEndpoint(port: 8010, name: "public")
    .WithEnvironment("FOUNDRY_ENDPOINT", options.Foundry.Endpoint)
    .WithEnvironment("FOUNDRY_MODEL", options.Foundry.Deployment)
    .WithEnvironment("FOUNDRY_KEY", options.Foundry.Key)
    .WithEnvironment("DAB_MCP_URL", ReferenceExpression.Create($"{dabServer.GetEndpoint("http")}/mcp"))
    .WaitFor(dabServer)
    .WithUrls(context =>
    {
        context.Urls.First().DisplayText = "Web Chat";
        context.Urls.RemoveRange(1, context.Urls.Count - 1);
    });

// Start the application

await builder.Build().RunAsync();

static class Extensions
{
    public static IResourceBuilder<ContainerResource> AddWebClient<TDab>(this IDistributedApplicationBuilder builder, string name, int externalPort, int internalPort, IResourceBuilder<TDab> dabServer, string? displayText = null, Action<IResourceBuilder<ContainerResource>>? configure = null)
        where TDab : ContainerResource
    {
        var directory = new DirectoryInfo("../" + name).FullName;

        var client = builder
            .AddDockerfile(name, directory)
            .WithHttpEndpoint(port: externalPort, targetPort: internalPort, name: "http")
            .WithIconName("Globe")
            .WithParentRelationship(dabServer)
            .WaitFor(dabServer)
            .WithUrls(context =>
            {
                context.Urls.First().DisplayText = $"Web Client ({displayText ?? name})";
                context.Urls.RemoveRange(1, context.Urls.Count - 1);
            });

        configure?.Invoke(client);
        return client;
    }

    public static IResourceBuilder<SqlServerDatabaseResource> AddSqlCommander(this IResourceBuilder<SqlServerDatabaseResource> db, string? name = null, int? externalPort = null)
    {
        ArgumentNullException.ThrowIfNull(db);

        var commander = db.ApplicationBuilder
            .AddContainer(name ?? "sqlcmdr-" + db.Resource.Name, "jerrynixon/sql-commander", "latest")
            .WithIconName("EyeTracking")
            .WithImageRegistry("docker.io")
            .WithHttpEndpoint(port: externalPort, targetPort: 8080, name: "http")
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