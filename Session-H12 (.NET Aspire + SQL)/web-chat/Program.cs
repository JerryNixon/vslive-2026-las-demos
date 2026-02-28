using WebChat;

var builder = WebApplication.CreateBuilder(args);

// --- Configuration + DI (fail fast with explicit messages) ---

var config = AiChatConfig.FromConfiguration(builder.Configuration);
builder.Services.AddAiChatClient(config);

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

// --- Health Endpoint ---

app.MapGet("/api/health", async (AiChatClient chat, CancellationToken ct) =>
    Results.Json(await chat.CheckHealthAsync(ct)));

// --- Settings Endpoint ---

app.MapGet("/api/settings", (AiChatClient chat) => Results.Json(new
{
    foundry = new { endpoint = chat.Config.FoundryEndpoint, model = chat.Config.FoundryModel, key = chat.Config.MaskedKey },
    mcp = new { url = chat.Config.DabMcpUrl }
}));

// --- Chat Endpoint ---

app.MapPost("/api/chat", async (ChatRequest request, AiChatClient chat, CancellationToken ct) =>
{
    var result = await chat.ChatAsync(request, ct);
    return Results.Json(result, statusCode: result.error ? 500 : 200);
});

await app.RunAsync();
