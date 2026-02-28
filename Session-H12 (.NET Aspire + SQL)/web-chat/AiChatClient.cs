using System.ClientModel;
using System.Diagnostics;
using System.Text.Json;
using Azure.AI.OpenAI;
using Microsoft.Extensions.AI;
using ModelContextProtocol.Client;

namespace WebChat;

// --- DTOs ---

public record ChatRequest(List<ChatMessageDto> Messages);
public record ChatMessageDto(string Role, string Content);
public record ChatResult(string answer, bool error = false, string? details = null, string? stackTrace = null);
public record HealthResult(string status, HealthConfig config, List<string> issues);
public record HealthConfig(string foundryEndpoint, string foundryModel, string foundryKey, string dabMcpUrl);

// --- Configuration ---

public record AiChatConfig(
    string FoundryEndpoint, string FoundryModel, string FoundryKey, string DabMcpUrl,
    int MaxMessages = 50, int MaxTotalChars = 100_000,
    int ToolCacheTtlMinutes = 5, int ToolCacheFailTtlSeconds = 10,
    int HealthCheckTimeoutSeconds = 30)
{
    public static AiChatConfig FromConfiguration(IConfiguration config)
    {
        var endpoint = config["FOUNDRY_ENDPOINT"]
            ?? throw new InvalidOperationException("FOUNDRY_ENDPOINT is not configured. Set it as an environment variable.");
        var model = config["FOUNDRY_MODEL"]
            ?? throw new InvalidOperationException("FOUNDRY_MODEL is not configured. Set it as an environment variable.");
        var key = config["FOUNDRY_KEY"]
            ?? throw new InvalidOperationException("FOUNDRY_KEY is not configured. Set it as an environment variable.");
        var mcpUrl = config["DAB_MCP_URL"]
            ?? throw new InvalidOperationException("DAB_MCP_URL is not configured. Set it as an environment variable.");

        if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var endpointUri))
        {
            throw new InvalidOperationException($"FOUNDRY_ENDPOINT is not a valid URI: '{endpoint}'");
        }

        if (endpointUri.Scheme != Uri.UriSchemeHttps)
        {
            throw new InvalidOperationException($"FOUNDRY_ENDPOINT must use HTTPS: '{endpoint}'");
        }

        if (!Uri.TryCreate(mcpUrl, UriKind.Absolute, out _))
        {
            throw new InvalidOperationException($"DAB_MCP_URL is not a valid URI: '{mcpUrl}'");
        }

        if (string.IsNullOrWhiteSpace(model))
        {
            throw new InvalidOperationException("FOUNDRY_MODEL is empty or whitespace.");
        }

        if (string.IsNullOrWhiteSpace(key))
        {
            throw new InvalidOperationException("FOUNDRY_KEY is empty or whitespace.");
        }

        return new AiChatConfig(endpoint, model, key, mcpUrl);
    }

    public string MaskedKey => FoundryKey.Length > 5 ? "..." + FoundryKey[^5..] : "***";
}

// --- AI Chat Client ---

public class AiChatClient(IChatClient chatClient, McpClientFactory mcpFactory, IHttpClientFactory httpFactory, IHostEnvironment env, ILogger<AiChatClient> logger, AiChatConfig config)
{
    private readonly bool _isDevelopment = env.IsDevelopment();
    private readonly TimeSpan _toolCacheTtl = TimeSpan.FromMinutes(config.ToolCacheTtlMinutes);
    private readonly TimeSpan _toolCacheFailTtl = TimeSpan.FromSeconds(config.ToolCacheFailTtlSeconds);

    private readonly SemaphoreSlim _toolCacheLock = new(1, 1);
    // Immutable snapshot of cached tools + ChatOptions, swapped atomically via volatile reference.
    private sealed record ToolCacheEntry(IList<McpClientTool> Tools, ChatOptions Options);
    private volatile ToolCacheEntry? _toolCache;
    // Stopwatch ticks (not DateTime) for monotonic, drift-free timing.
    // Uses Volatile.Read/Write rather than the volatile keyword because
    // the C# spec does not guarantee atomic reads of volatile longs on 32-bit runtimes.
    private long _toolsCachedAtTimestamp;
    private volatile bool _lastToolFetchFailed;

    private const string SystemPrompt =
        """
        You are a helpful assistant with access to database tools.
        Use the available tools to query the database when users ask about products, categories, inventory, or warehouses.
        Always use tools to get real data — never make up answers.
        Keep responses concise and formatted clearly.
        """;

    public AiChatConfig Config => config;

    public async Task<ChatResult> ChatAsync(ChatRequest request, CancellationToken ct = default)
    {
        // Validate request
        if (request.Messages is null || request.Messages.Count == 0)
            return new ChatResult("**ERROR:** No messages provided in request.", error: true);

        // Strip client-supplied system and thinking messages before validation.
        // System: prevents prompt injection from misconfigured proxies or SSRF.
        // Thinking: model reasoning traces (e.g. gpt-5-mini) that shouldn't round-trip.
        static bool IsStrippedRole(string? role) =>
            string.Equals(role, "system", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(role, "thinking", StringComparison.OrdinalIgnoreCase);

        var strippedCount = request.Messages.Count(m => IsStrippedRole(m.Role));
        if (strippedCount > 0)
            logger.LogWarning("Stripped {Count} non-conversation message(s) (system/thinking) from request", strippedCount);

        var userMessages = request.Messages
            .Where(m => !IsStrippedRole(m.Role))
            .ToList();

        if (userMessages.Count > config.MaxMessages)
            return new ChatResult(
                $"**ERROR:** Conversation too long ({userMessages.Count} messages). " +
                $"Maximum is {config.MaxMessages}. Start a new conversation.",
                error: true);

        var totalChars = userMessages.Sum(m => (m.Content?.Length ?? 0));
        if (totalChars > config.MaxTotalChars)
            return new ChatResult(
                $"**ERROR:** Conversation exceeds char budget (~{totalChars:N0} chars, max {config.MaxTotalChars:N0}). " +
                $"Start a new conversation.",
                error: true);

        // Resolve MCP tools (cached, refreshed every 5 min)
        IList<McpClientTool> tools;
        try
        {
            tools = await GetToolsCachedAsync(ct);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "MCP tool fetch failed for {DabMcpUrl}", config.DabMcpUrl);
            return new ChatResult(
                $"**MCP ERROR:** Cannot reach DAB at `{config.DabMcpUrl}`. Is the container running?\n\n" +
                $"`{ex.GetType().Name}: {ex.Message}`",
                error: true);
        }

        // Build message list (server-side system prompt only; client system messages already stripped)
        var messages = new List<ChatMessage> { new(ChatRole.System, SystemPrompt) };

        foreach (var msg in userMessages)
        {
            if (string.IsNullOrWhiteSpace(msg.Role))
                return new ChatResult("**ERROR:** Message has empty role.", error: true);

            var role = msg.Role.ToLowerInvariant() switch
            {
                "user" => ChatRole.User,
                "assistant" => ChatRole.Assistant,
                _ => (ChatRole?)null
            };

            if (role is null)
                return new ChatResult($"**ERROR:** Unrecognized message role: `{msg.Role}`. Expected `user` or `assistant`.", error: true);

            messages.Add(new ChatMessage(role.Value, msg.Content ?? ""));
        }

        // Call AI model (ChatOptions cached alongside tools in ToolCacheEntry)
        var chatOptions = _toolCache?.Options ?? new ChatOptions { Tools = [.. tools] };

        try
        {
            var response = await chatClient.GetResponseAsync(messages, chatOptions, ct);
            var answer = string.IsNullOrWhiteSpace(response.Text)
                ? "(Model returned only tool calls — no final answer generated. Try rephrasing your question.)"
                : response.Text;
            return new ChatResult(answer);
        }
        catch (ClientResultException ex)
        {
            logger.LogError(ex, "AI model error: HTTP {Status} from {Endpoint}/{Model}", ex.Status, config.FoundryEndpoint, config.FoundryModel);
            return new ChatResult(
                $"**AI MODEL ERROR:** The model at `{config.FoundryEndpoint}` returned an error.\n\n" +
                $"Model: `{config.FoundryModel}`\n\n" +
                $"`{ex.GetType().Name}` (HTTP {ex.Status}): {ex.Message}",
                error: true);
        }
        catch (HttpRequestException ex)
        {
            logger.LogError(ex, "Network error reaching AI endpoint {Endpoint}", config.FoundryEndpoint);
            return new ChatResult(
                $"**NETWORK ERROR:** Cannot reach AI endpoint `{config.FoundryEndpoint}`.\n\n" +
                $"`{ex.GetType().Name}`: {ex.Message}",
                error: true);
        }
        catch (TaskCanceledException ex)
        {
            logger.LogWarning("AI request timeout for {Endpoint}/{Model}", config.FoundryEndpoint, config.FoundryModel);
            return new ChatResult(
                $"**TIMEOUT:** The AI model did not respond in time.\n\n" +
                $"Endpoint: `{config.FoundryEndpoint}`, Model: `{config.FoundryModel}`\n\n`{ex.Message}`",
                error: true);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error in ChatAsync");
            // Only include stack trace in Development to avoid leaking internal paths
            return new ChatResult(
                $"**UNEXPECTED ERROR:** `{ex.GetType().Name}` — {ex.Message}",
                error: true,
                details: ex.InnerException?.Message,
                stackTrace: _isDevelopment ? ex.StackTrace : null);
        }
    }

    public async Task<HealthResult> CheckHealthAsync(CancellationToken ct = default)
    {
        var issues = new List<string>();

        // Check MCP/DAB connectivity (uses cached tools when fresh)
        try
        {
            var tools = await GetToolsCachedAsync(ct);
            if (tools.Count == 0)
                issues.Add("MCP connected but returned 0 tools — DAB may have no entities configured.");
        }
        catch (Exception ex)
        {
            issues.Add($"MCP/DAB unreachable at '{config.DabMcpUrl}': {ex.GetType().Name} — {ex.Message}");
        }

        // Check AI endpoint reachability (hits /models and verifies the specific deployment exists)
        try
        {
            using var http = httpFactory.CreateClient();
            http.Timeout = TimeSpan.FromSeconds(config.HealthCheckTimeoutSeconds);
            var modelsUrl = config.FoundryEndpoint.TrimEnd('/') + "/openai/v1/models";
            using var request = new HttpRequestMessage(HttpMethod.Get, modelsUrl);
            request.Headers.Add("api-key", config.FoundryKey);
            var response = await http.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode)
            {
                issues.Add($"AI models endpoint returned {(int)response.StatusCode} at '{modelsUrl}'.");
            }
            else
            {
                // Parse the /models JSON response to verify the specific deployment exists
                var body = await response.Content.ReadAsStringAsync(ct);
                try
                {
                    using var doc = JsonDocument.Parse(body);
                    var found = false;
                    if (doc.RootElement.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in data.EnumerateArray())
                        {
                            if (item.TryGetProperty("id", out var id) &&
                                string.Equals(id.GetString(), config.FoundryModel, StringComparison.OrdinalIgnoreCase))
                            {
                                found = true;
                                break;
                            }
                        }
                    }
                    if (!found)
                        issues.Add($"AI endpoint is reachable but deployment '{config.FoundryModel}' was not found in /models response.");
                }
                catch (JsonException)
                {
                    issues.Add("AI /models endpoint returned non-JSON response.");
                }
            }
        }
        catch (Exception ex)
        {
            issues.Add($"AI endpoint unreachable at '{config.FoundryEndpoint}': {ex.GetType().Name} — {ex.Message}");
        }

        return new HealthResult(
            status: issues.Count == 0 ? "healthy" : "degraded",
            config: new HealthConfig(config.FoundryEndpoint, config.FoundryModel, config.MaskedKey, config.DabMcpUrl),
            issues: issues
        );
    }

    private async Task<IList<McpClientTool>> GetToolsCachedAsync(CancellationToken ct = default)
    {
        var now = Stopwatch.GetTimestamp();
        var ttl = _lastToolFetchFailed ? _toolCacheFailTtl : _toolCacheTtl;
        var cachedAt = Volatile.Read(ref _toolsCachedAtTimestamp);

        var cache = _toolCache;
        if (cache is not null && Stopwatch.GetElapsedTime(cachedAt, now) < ttl)
            return cache.Tools;

        // Fast-fail during failure cooldown — avoid queueing callers on the semaphore
        // when the MCP server is known to be down.
        if (_lastToolFetchFailed && cache is null && Stopwatch.GetElapsedTime(cachedAt, now) < _toolCacheFailTtl)
            throw new InvalidOperationException($"MCP tool fetch recently failed; retrying after {config.ToolCacheFailTtlSeconds}s cooldown.");

        await _toolCacheLock.WaitAsync(ct);
        try
        {
            // Double-check after acquiring lock
            now = Stopwatch.GetTimestamp();
            ttl = _lastToolFetchFailed ? _toolCacheFailTtl : _toolCacheTtl;
            cachedAt = Volatile.Read(ref _toolsCachedAtTimestamp);
            cache = _toolCache;
            if (cache is not null && Stopwatch.GetElapsedTime(cachedAt, now) < ttl)
                return cache.Tools;

            var mcpClient = await mcpFactory.GetClientAsync(ct);
            var tools = await mcpClient.ListToolsAsync(cancellationToken: ct);
            _toolCache = new ToolCacheEntry(tools, new ChatOptions { Tools = [.. tools] });
            Volatile.Write(ref _toolsCachedAtTimestamp, Stopwatch.GetTimestamp());
            _lastToolFetchFailed = false;
            logger.LogInformation("MCP tool cache refreshed: {ToolCount} tools from {DabMcpUrl}", tools.Count, config.DabMcpUrl);
            return tools;
        }
        catch
        {
            // Short-circuit: cache the failure so we don't hammer a dead service.
            // Fast-fail path above prevents callers from piling up on the semaphore.
            Volatile.Write(ref _toolsCachedAtTimestamp, Stopwatch.GetTimestamp());
            _lastToolFetchFailed = true;
            _toolCache = null;
            await mcpFactory.InvalidateClientAsync(); // Dispose stale connection and force reconnect
            throw;
        }
        finally
        {
            _toolCacheLock.Release();
        }
    }

}

// --- Retryable MCP Client Factory ---

/// <summary>
/// Manages the MCP client lifecycle with retry-on-failure semantics.
/// A failed connection is not permanently cached — the next call retries.
/// Stale connections are invalidated when tool fetching fails.
/// Registered as singleton; the DI container calls DisposeAsync on shutdown.
/// </summary>
public sealed class McpClientFactory(AiChatConfig config) : IAsyncDisposable
{
    private readonly SemaphoreSlim _lock = new(1, 1);
    private volatile McpClient? _client;

    public async Task<McpClient> GetClientAsync(CancellationToken ct = default)
    {
        if (_client is not null)
            return _client;

        await _lock.WaitAsync(ct);
        try
        {
            if (_client is not null)
                return _client;

            var transport = new HttpClientTransport(new HttpClientTransportOptions
            {
                Endpoint = new Uri(config.DabMcpUrl),
                Name = "dab-mcp",
                TransportMode = HttpTransportMode.StreamableHttp
            });
            _client = await McpClient.CreateAsync(transport, cancellationToken: ct);
            return _client;
        }
        catch
        {
            _client = null;
            throw;
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>
    /// Invalidates the cached client so the next GetClientAsync call reconnects.
    /// Acquires the lock to prevent racing with GetClientAsync, then disposes
    /// the old client to release the underlying HTTP transport immediately.
    /// Called when tool fetching fails, indicating the MCP server may have restarted.
    /// </summary>
    public async Task InvalidateClientAsync()
    {
        await _lock.WaitAsync();
        try
        {
            var old = _client;
            _client = null;
            if (old is not null)
            {
                try { await old.DisposeAsync(); }
                catch { /* Best-effort cleanup — the connection is already broken */ }
            }
        }
        finally
        {
            _lock.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_client is not null)
            await _client.DisposeAsync();
    }
}

// --- DI Registration ---

public static class AiChatServiceExtensions
{
    public static IServiceCollection AddAiChatClient(this IServiceCollection services, AiChatConfig config)
    {
        services.AddSingleton(config);
        services.AddHttpClient();

        services.AddSingleton<McpClientFactory>();

        services.AddSingleton<IChatClient>(sp =>
        {
            try
            {
                var credential = new ApiKeyCredential(config.FoundryKey);
                var azureClient = new AzureOpenAIClient(new Uri(config.FoundryEndpoint), credential);
                IChatClient client = azureClient.GetChatClient(config.FoundryModel).AsIChatClient();
                var loggerFactory = sp.GetRequiredService<ILoggerFactory>();
                return new ChatClientBuilder(client)
                    .UseLogging(loggerFactory)
                    .UseFunctionInvocation()
                    .Build();
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException(
                    $"Failed to create Azure AI chat client. Endpoint='{config.FoundryEndpoint}', Model='{config.FoundryModel}'. " +
                    $"({ex.GetType().Name}: {ex.Message})", ex);
            }
        });

        services.AddSingleton<AiChatClient>();

        return services;
    }
}
