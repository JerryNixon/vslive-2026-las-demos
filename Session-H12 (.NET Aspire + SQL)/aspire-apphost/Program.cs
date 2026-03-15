// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

var builder = DistributedApplication.CreateBuilder(args);

var foundryEndpoint = builder.AddParameter("Foundry-Endpoint", secret: true)
    .WithCustomInput(p => new()
    {
        Name = p.Name,
        Label = "Azure AI Foundry Endpoint",
        Placeholder = "For example, https://your-resource.cognitiveservices.azure.com",
        InputType = InputType.Text,
        Description = "Find your endpoint here: [Azure AI Foundry](https://ai.azure.com)",
        EnableDescriptionMarkdown = true
    });
var foundryKey = builder.AddParameter("Foundry-Key", secret: true)
    .WithCustomInput(p => new()
    {
        Name = p.Name,
        Label = "Azure AI Foundry API Key",
        Placeholder = "For example, ABC123XYZ456",
        InputType = InputType.Text
    });
var foundryDeployment = builder.AddParameter("Foundry-Deployment", secret: true)
    .WithCustomInput(p => new()
    {
        Name = p.Name,
        Label = "Azure AI Foundry Deployment",
        Placeholder = "For example, my-deployment-name",
        InputType = InputType.Text
    });
var sqlPassword = builder.AddParameter("sql-password", secret: true)
    .WithCustomInput(p => new()
    {
        Name = p.Name,
        Label = "SQL Server Password",
        Placeholder = "Enter your SQL Server password",
        InputType = InputType.Text
    });

var sqlServer = builder
    .AddSqlServer("sql-server", password: sqlPassword, port: 8001)
    .WithDataVolume("sql-data")
    .WithLifetime(ContainerLifetime.Persistent);

var catalogDb = sqlServer.AddDatabase("CatalogDb").AddSqlCommander(externalPort: 8002);
var catalogSqlproj = builder.AddSqlProject<Projects.CatalogDb>("sqlproj-" + catalogDb.Resource.Name)
    .WithSkipWhenDeployed()
    .WithReference(catalogDb);

var inventoryDb = sqlServer.AddDatabase("InventoryDb").AddSqlCommander(externalPort: 8003);
var inventorySqlproj = builder.AddSqlProject<Projects.InventoryDb>("sqlproj-" + inventoryDb.Resource.Name)
    .WithSkipWhenDeployed()
    .WithReference(inventoryDb);

var configDir = Path.Combine(Path.Combine(builder.AppHostDirectory, "..", "data-api"));
var config1 = new FileInfo(Path.Combine(configDir, "dab-config.json"));
var config2 = new FileInfo(Path.Combine(configDir, "dab-config-catalog.json"));
var config3 = new FileInfo(Path.Combine(configDir, "dab-config-inventory.json"));

var dabServer = builder
    .AddDataAPIBuilder("data-api", 8004).WithIconName("Drag")
    .WithConfigFile(config1, config2, config3)
    .WithImageTag("2.0.0-rc")
    .WithEnvironment("CATALOG_CONNECTION_STRING", catalogDb)
    .WithEnvironment("INVENTORY_CONNECTION_STRING", inventoryDb)
    .WaitForCompletion(catalogSqlproj)
    .WaitForCompletion(inventorySqlproj);

builder.AddWebClient("web-app-aspnet", 8006, 8080, dabServer, "ASPNET").WithReference(dabServer);
builder.AddWebClient("web-app-react", 8007, 3000, dabServer, "React", c => c.WithEnvironment("NODE_TLS_REJECT_UNAUTHORIZED", "0")).WithReference(dabServer);
builder.AddWebClient("web-app-python", 8008, 3000, dabServer, "Python").WithReference(dabServer);
builder.AddWebClient("web-app-java", 8009, 3000, dabServer, "Java").WithReference(dabServer);

builder
    .AddMcpInspector("mcp-inspector", o => o.InspectorVersion = "0.20.0")
    .WithIconName("EyeTracking")
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

builder.AddProject<Projects.WebChat>("web-chat")
    .WithIconName("Chat")
    .WithHttpEndpoint(port: 8010, name: "public")
    .WithEnvironment("FOUNDRY_ENDPOINT", foundryEndpoint)
    .WithEnvironment("FOUNDRY_MODEL", foundryDeployment)
    .WithEnvironment("FOUNDRY_KEY", foundryKey)
    .WithEnvironment("MCP_URL", ReferenceExpression.Create($"{dabServer.GetEndpoint("http")}/mcp"))
    .WaitFor(dabServer)
    .WithUrls(context =>
    {
        context.Urls.First().DisplayText = "Web Chat";
        context.Urls.RemoveRange(1, context.Urls.Count - 1);
    });

await builder.Build().RunAsync();

static class Extensions
{
    public static IResourceBuilder<ContainerResource> AddWebClient<TDab>(
        this IDistributedApplicationBuilder builder, string name, int externalPort, int internalPort,
        IResourceBuilder<TDab> dabServer, string? displayText = null,
        Action<IResourceBuilder<ContainerResource>>? configure = null) where TDab : ContainerResource
    {
        var contextDir = Path.GetFullPath(Path.Combine(builder.AppHostDirectory, "..", name));
        if (!Directory.Exists(contextDir))
            throw new InvalidOperationException($"Dockerfile context directory not found: '{contextDir}'");
        var client = builder
            .AddDockerfile(name, contextDir)
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

    public static IResourceBuilder<SqlServerDatabaseResource> AddSqlCommander(
        this IResourceBuilder<SqlServerDatabaseResource> db, string? name = null, int? externalPort = null)
    {
        ArgumentNullException.ThrowIfNull(db);
        db.ApplicationBuilder
            .AddContainer(name ?? "sqlcmdr-" + db.Resource.Name, "jerrynixon/sql-commander", "latest")
            .WithIconName("EyeTracking")
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