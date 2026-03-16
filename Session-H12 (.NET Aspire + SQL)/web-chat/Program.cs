using WebChat;

var builder = WebApplication.CreateBuilder(args);

var config = AiChatConfig.FromConfiguration(builder.Configuration);
builder.Services.AddAiChatClient(config);
// 2x headroom over MaxTotalChars to account for JSON framing (keys, quotes, arrays) and multi-byte UTF-8 chars
builder.WebHost.ConfigureKestrel(k => k.Limits.MaxRequestBodySize = config.MaxTotalChars * 2);

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/health", async (AiChatClient chat, CancellationToken ct) =>
{
    var result = await chat.CheckHealthAsync(ct);
    return Results.Json(result, statusCode: result.issues.Count == 0 ? 200 : 503);
});

app.MapGet("/api/settings", (AiChatClient chat) =>
    Results.Json(new
    {
        foundry = new { endpoint = chat.Config.FoundryEndpoint, model = chat.Config.FoundryModel, key = chat.Config.MaskedKey },
        mcp = new { url = chat.Config.McpUrl }
    }));

app.MapPost("/api/chat", async (ChatRequest request, AiChatClient chat, CancellationToken ct) =>
{
    var result = await chat.ChatAsync(request, ct);
    return Results.Json(result, statusCode: result.statusCode);
});

await app.RunAsync();
