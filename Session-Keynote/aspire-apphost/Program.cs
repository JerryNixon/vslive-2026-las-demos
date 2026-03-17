var builder = DistributedApplication.CreateBuilder(args);

var sqlPassword = builder.AddParameter("sql-password", secret: true);

var sqlServer = builder
    .AddSqlServer("keynote-sql", password: sqlPassword, port: 8011)
    .WithDataVolume("keynote-sql-data")
    .WithLifetime(ContainerLifetime.Persistent);

var agentsDb = sqlServer.AddDatabase("AgentsDb");

var sqlProj = builder
    .AddSqlProject<Projects.AgentsDb>("sqlproj-AgentsDb")
    .WithReference(agentsDb);

var configFile = new FileInfo(Path.Combine(builder.AppHostDirectory, "..", "data-api", "dab-config.json"));

var dabServer = builder
    .AddDataAPIBuilder("keynote-dab", 8012)
    .WithConfigFile(configFile)
    .WithImageTag("2.0.0-rc")
    .WithEnvironment("DATABASE_CONNECTION_STRING", agentsDb)
    .WaitForCompletion(sqlProj);

builder.AddProject<Projects.AgentsConsole>("agents-console")
    .WithEnvironment("DAB_MCP_ENDPOINT", ReferenceExpression.Create($"{dabServer.GetEndpoint("http")}/mcp"))
    .WaitFor(dabServer);

await builder.Build().RunAsync();
