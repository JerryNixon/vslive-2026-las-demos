using System.Diagnostics;
using System.Text.Json;
using Azure;
using Azure.AI.Inference;
using Azure.Core;
using Azure.Core.Pipeline;
using Azure.Identity;
using Microsoft.Extensions.AI;
using ChatRole = Microsoft.Extensions.AI.ChatRole;
using ModelContextProtocol.Client;

namespace WebChat;

public record ChatRequest(List<ChatMessageDto> Messages);
public record ChatMessageDto(string Role, string? Content);
public record ChatResult(string answer, bool error = false, int statusCode = 200, string? details = null, string? stackTrace = null);
public record HealthResult(string status, HealthConfig config, List<string> issues);
public record HealthConfig(string foundryEndpoint, string foundryModel, string foundryKey, string mcpUrl);

public record AiChatConfig(
    string FoundryEndpoint, string FoundryModel, string FoundryKey, string McpUrl,
    bool IsProjectEndpoint = false,
    int MaxMessages = 50, int MaxTotalChars = 100_000,
    int MaxMessageChars = 50_000,
    int ToolCacheTtlMinutes = 5, int ToolCacheFailTtlSeconds = 10,
    int HealthCheckTimeoutSeconds = 30,
    string? SystemPrompt = null)
{
    public static AiChatConfig FromConfiguration(IConfiguration config)
    {
        var endpoint = config["FOUNDRY_ENDPOINT"]
            ?? throw new InvalidOperationException("FOUNDRY_ENDPOINT is not configured. Set it as an environment variable.");
        var key = config["FOUNDRY_KEY"]
            ?? throw new InvalidOperationException("FOUNDRY_KEY is not configured. Set it as an environment variable.");
        var model = config["FOUNDRY_MODEL"]
            ?? throw new InvalidOperationException("FOUNDRY_MODEL is not configured. Set it as an environment variable.");
        var mcpUrl = config["MCP_URL"]
            ?? throw new InvalidOperationException("MCP_URL is not configured. Set it as an environment variable.");

        if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var endpointUri))
        {
            throw new InvalidOperationException($"FOUNDRY_ENDPOINT is not a valid URI: '{endpoint}'");
        }

        if (endpointUri.Scheme != Uri.UriSchemeHttps)
        {
            throw new InvalidOperationException($"FOUNDRY_ENDPOINT must use HTTPS: '{endpoint}'");
        }

        // Detect Azure AI Foundry project URL (e.g. https://resource.services.ai.azure.com/api/projects/{project}).
        // The correct inference endpoint is {base-host}/models, authenticated via DefaultAzureCredential
        // with scope https://ai.azure.com/.default — NOT via API key.
        // See: https://github.com/Azure/azure-sdk-for-net/blob/main/sdk/ai/Azure.AI.Projects/samples/Sample9_InferenceChatClient.md
        bool isProjectEndpoint = false;
        if (endpointUri.AbsolutePath.StartsWith("/api/projects/", StringComparison.OrdinalIgnoreCase))
        {
            isProjectEndpoint = true;
            endpoint = $"{endpointUri.GetLeftPart(UriPartial.Authority)}/models";
            Console.Error.WriteLine($"INFO: Azure AI Foundry project URL detected. Inference endpoint: {endpoint}");
            Console.Error.WriteLine($"INFO: Auth uses DefaultAzureCredential (scope: https://ai.azure.com/.default), not the API key.");
        }

        // Detect when user pastes a full chat completions request URL instead of a base endpoint.
        // e.g. https://my-resource.cognitiveservices.azure.com/openai/deployments/my-model/chat/completions?api-version=...
        var path = endpointUri.AbsolutePath;
        if (path.Contains("/openai/deployments/", StringComparison.OrdinalIgnoreCase) ||
            path.Contains("/chat/completions", StringComparison.OrdinalIgnoreCase) ||
            path.Contains("/completions", StringComparison.OrdinalIgnoreCase))
        {
            var baseUrl = $"{endpointUri.Scheme}://{endpointUri.Host}";
            throw new InvalidOperationException(
                $"FOUNDRY_ENDPOINT looks like a full request URL, not a base endpoint. " +
                $"Remove the path and query string — use just the base URL. " +
                $"For example: '{baseUrl}' instead of '{endpoint}'");
        }

        // Normalise the endpoint string (trim trailing slash).
        // For project URLs the endpoint was already rewritten above; for all others, derive it from the parsed URI.
        if (!isProjectEndpoint)
        {
            endpoint = endpointUri.ToString().TrimEnd('/');
        }

        if (!Uri.TryCreate(mcpUrl, UriKind.Absolute, out var mcpUri))
        {
            throw new InvalidOperationException($"MCP_URL is not a valid URI: '{mcpUrl}'");
        }

        if (mcpUri.Scheme != Uri.UriSchemeHttps && !mcpUri.IsLoopback)
        {
            Console.Error.WriteLine($"WARNING: MCP_URL uses {mcpUri.Scheme}:// on a non-loopback host. Use HTTPS in production.");
        }

        if (string.IsNullOrWhiteSpace(model))
        {
            throw new InvalidOperationException("FOUNDRY_MODEL is empty or whitespace.");
        }

        if (string.IsNullOrWhiteSpace(key))
        {
            throw new InvalidOperationException("FOUNDRY_KEY is empty or whitespace.");
        }

        return new AiChatConfig(endpoint, model, key, mcpUrl, isProjectEndpoint);
    }

    public string MaskedKey => FoundryKey.Length > 8 ? "***" + FoundryKey[^4..] : "***";
}

public sealed class AiChatClient(IChatClient chatClient, McpClientFactory mcpFactory, IHttpClientFactory httpFactory, IHostEnvironment env, ILogger<AiChatClient> logger, AiChatConfig config)
{
    private readonly bool _isDevelopment = env.IsDevelopment();
    private readonly TimeSpan _toolCacheTtl = TimeSpan.FromMinutes(config.ToolCacheTtlMinutes);
    private readonly TimeSpan _toolCacheFailTtl = TimeSpan.FromSeconds(config.ToolCacheFailTtlSeconds);

    private readonly SemaphoreSlim _toolCacheLock = new(1, 1);
    private sealed record ToolCacheEntry(IReadOnlyList<McpClientTool> Tools);
    private volatile ToolCacheEntry? _toolCache;
    private long _toolsCachedAtTimestamp;
    private volatile bool _lastToolFetchFailed;

    private static readonly string DefaultSystemPrompt =
        """
        You are a helpful assistant with access to database tools.
        Use the available tools to query the database when users ask about products, categories, inventory, or warehouses.
        Always use tools to get real data — never make up answers.
        Keep responses concise and formatted clearly.
        """;

    private readonly string _systemPrompt = config.SystemPrompt ?? DefaultSystemPrompt;

    public AiChatConfig Config => config;

    public async Task<ChatResult> ChatAsync(ChatRequest request, CancellationToken ct = default)
    {
        if (request.Messages is null || request.Messages.Count == 0)
            return new ChatResult("**ERROR:** No messages provided in request.", error: true, statusCode: 400);

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
                error: true, statusCode: 400);

        var totalChars = 0;
        foreach (var m in userMessages)
        {
            var len = m.Content?.Length ?? 0;
            if (len > config.MaxMessageChars)
                return new ChatResult(
                    $"**ERROR:** A single message is too large ({len:N0} chars, max {config.MaxMessageChars:N0}). " +
                    $"Shorten it and try again.",
                    error: true, statusCode: 400);
            totalChars += len;
        }

        if (totalChars > config.MaxTotalChars)
            return new ChatResult(
                $"**ERROR:** Conversation exceeds char budget (~{totalChars:N0} chars, max {config.MaxTotalChars:N0}). " +
                $"Start a new conversation.",
                error: true, statusCode: 400);

        IReadOnlyList<McpClientTool> tools;
        try
        {
            tools = await GetToolsCachedAsync(ct);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "MCP tool fetch failed for {McpUrl}", config.McpUrl);
            await mcpFactory.InvalidateClientAsync();
            return new ChatResult(
                $"**MCP ERROR:** Cannot reach MCP server at `{config.McpUrl}`. Is it running?",
                error: true, statusCode: 502,
                details: _isDevelopment ? $"{ex.GetType().Name}: {ex.Message}" : null);
        }

        var messages = new List<ChatMessage> { new(ChatRole.System, _systemPrompt) };

        foreach (var msg in userMessages)
        {
            if (string.IsNullOrWhiteSpace(msg.Role))
                return new ChatResult("**ERROR:** Message has empty role.", error: true, statusCode: 400);

            var role = msg.Role switch
            {
                var r when r.Equals("user", StringComparison.OrdinalIgnoreCase) => ChatRole.User,
                var r when r.Equals("assistant", StringComparison.OrdinalIgnoreCase) => ChatRole.Assistant,
                _ => (ChatRole?)null
            };

            if (role is null)
                return new ChatResult($"**ERROR:** Unrecognized message role: `{msg.Role}`. Expected `user` or `assistant`.", error: true, statusCode: 400);

            messages.Add(new ChatMessage(role.Value, msg.Content ?? ""));
        }

        var chatOptions = new ChatOptions { Tools = [.. tools] };

        try
        {
            var response = await chatClient.GetResponseAsync(messages, chatOptions, ct);
            var answer = string.IsNullOrWhiteSpace(response.Text)
                ? "(Model returned only tool calls — no final answer generated. Try rephrasing your question.)"
                : response.Text;
            return new ChatResult(answer);
        }
        catch (RequestFailedException ex)
        {
            logger.LogError(ex, "AI model error: HTTP {Status} from {Endpoint}/{Model}", ex.Status, config.FoundryEndpoint, config.FoundryModel);
            var keyHint = ex.Status is 401 or 403
                ? "\n\n**Likely cause:** The API key is wrong. Check `FOUNDRY_KEY`."
                : "";
            return new ChatResult(
                $"**AI MODEL ERROR:** The model at `{config.FoundryEndpoint}` returned an error.\n\n" +
                $"Model: `{config.FoundryModel}`\n\n" +
                (_isDevelopment ? $"`{ex.GetType().Name}` (HTTP {ex.Status}): {ex.Message}{keyHint}" : $"HTTP {ex.Status}{keyHint}"),
                error: true, statusCode: 502);
        }
        catch (HttpRequestException ex)
        {
            logger.LogError(ex, "Network error reaching AI endpoint {Endpoint}", config.FoundryEndpoint);
            return new ChatResult(
                $"**NETWORK ERROR:** Cannot reach AI endpoint `{config.FoundryEndpoint}`.",
                error: true, statusCode: 502,
                details: _isDevelopment ? $"{ex.GetType().Name}: {ex.Message}" : null);
        }
        catch (TaskCanceledException ex)
        {
            if (ct.IsCancellationRequested)
            {
                logger.LogInformation("Client disconnected during AI request to {Endpoint}/{Model}", config.FoundryEndpoint, config.FoundryModel);
                throw; // Propagate cancellation — the client is gone.
            }

            logger.LogWarning("AI request timeout for {Endpoint}/{Model}", config.FoundryEndpoint, config.FoundryModel);
            return new ChatResult(
                $"**TIMEOUT:** The AI model did not respond in time.\n\n" +
                $"Endpoint: `{config.FoundryEndpoint}`, Model: `{config.FoundryModel}`",
                error: true, statusCode: 504,
                details: _isDevelopment ? ex.Message : null);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error in ChatAsync");
            return new ChatResult(
                _isDevelopment
                    ? $"**UNEXPECTED ERROR:** `{ex.GetType().Name}` \u2014 {ex.Message}"
                    : "**UNEXPECTED ERROR:** An internal error occurred.",
                error: true, statusCode: 500,
                details: _isDevelopment ? ex.InnerException?.Message : null,
                stackTrace: _isDevelopment ? ex.StackTrace : null);
        }
    }

    public async Task<HealthResult> CheckHealthAsync(CancellationToken ct = default)
    {
        var issues = new List<string>();

        try
        {
            using var mcpCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            mcpCts.CancelAfter(TimeSpan.FromSeconds(config.HealthCheckTimeoutSeconds));
            var tools = await GetToolsCachedAsync(mcpCts.Token);
            if (tools.Count == 0)
                issues.Add("MCP connected but returned 0 tools — verify the MCP server has tools configured.");
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            issues.Add($"MCP health check timed out after {config.HealthCheckTimeoutSeconds}s for '{config.McpUrl}'.");
        }
        catch (Exception ex)
        {
            issues.Add($"MCP server unreachable at '{config.McpUrl}': {ex.GetType().Name} — {ex.Message}");
        }

        try
        {
            using var http = httpFactory.CreateClient();
            http.Timeout = TimeSpan.FromSeconds(config.HealthCheckTimeoutSeconds);

            if (config.IsProjectEndpoint)
            {
                // For Azure AI Foundry project endpoints, the /models listing endpoint doesn't
                // support GET requests (returns 404). Instead, verify connectivity by checking
                // that we can get a bearer token and that the base host is reachable.
                var aadCredential = new DefaultAzureCredential();
                try
                {
                    var tokenCtx = new Azure.Core.TokenRequestContext(["https://ai.azure.com/.default"]);
                    var token = await aadCredential.GetTokenAsync(tokenCtx, ct);
                    if (string.IsNullOrWhiteSpace(token.Token))
                        issues.Add("DefaultAzureCredential returned an empty token. Ensure Azure CLI is logged in or a managed identity is configured.");
                    // Connectivity check: HEAD the base models inference URL
                    using var headReq = new HttpRequestMessage(HttpMethod.Head,
                        config.FoundryEndpoint.TrimEnd('/') + "/chat/completions");
                    headReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token.Token);
                    // HEAD may return 405 (method not allowed) which still means the server is reachable.
                    var headResp = await http.SendAsync(headReq, ct);
                    if ((int)headResp.StatusCode is 0 or >= 500)
                        issues.Add($"AI Foundry endpoint connectivity check failed (HTTP {(int)headResp.StatusCode}) at '{config.FoundryEndpoint}'.");
                }
                catch (Exception aadEx)
                {
                    issues.Add($"DefaultAzureCredential error: {aadEx.GetType().Name} — {aadEx.Message}");
                }
            }
            else
            {
                var modelsUrl = config.FoundryEndpoint.TrimEnd('/') + "/models";
                using var request = new HttpRequestMessage(HttpMethod.Get, modelsUrl);
                request.Headers.Add("api-key", config.FoundryKey);
                var response = await http.SendAsync(request, ct);
                if (!response.IsSuccessStatusCode)
                {
                    var hint = (int)response.StatusCode is 401 or 403
                        ? " Check that FOUNDRY_KEY is correct."
                        : "";
                    issues.Add($"AI models endpoint returned {(int)response.StatusCode} at '{modelsUrl}'.{hint}");
                }
                else
                {
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
        }
        catch (Exception ex)
        {
            issues.Add($"AI endpoint unreachable at '{config.FoundryEndpoint}': {ex.GetType().Name} — {ex.Message}");
        }

        return new HealthResult(
            status: issues.Count == 0 ? "healthy" : "degraded",
            config: new HealthConfig(config.FoundryEndpoint, config.FoundryModel, config.MaskedKey, config.McpUrl),
            issues: issues
        );
    }

    private async Task<IReadOnlyList<McpClientTool>> GetToolsCachedAsync(CancellationToken ct = default)
    {
        var now = Stopwatch.GetTimestamp();
        var ttl = _lastToolFetchFailed ? _toolCacheFailTtl : _toolCacheTtl;
        var cachedAt = Volatile.Read(ref _toolsCachedAtTimestamp);

        var cache = _toolCache;
        if (cache is not null && Stopwatch.GetElapsedTime(cachedAt, now) < ttl)
            return cache.Tools;

        if (_lastToolFetchFailed && cache is null && Stopwatch.GetElapsedTime(cachedAt, now) < _toolCacheFailTtl)
            throw new InvalidOperationException($"MCP tool fetch recently failed; retrying after {config.ToolCacheFailTtlSeconds}s cooldown.");

        await _toolCacheLock.WaitAsync(ct);
        try
        {
            now = Stopwatch.GetTimestamp();
            ttl = _lastToolFetchFailed ? _toolCacheFailTtl : _toolCacheTtl;
            cachedAt = Volatile.Read(ref _toolsCachedAtTimestamp);
            cache = _toolCache;
            if (cache is not null && Stopwatch.GetElapsedTime(cachedAt, now) < ttl)
                return cache.Tools;

            var mcpClient = await mcpFactory.GetClientAsync(ct);
            var tools = (IReadOnlyList<McpClientTool>)await mcpClient.ListToolsAsync(cancellationToken: ct);
            _toolCache = new ToolCacheEntry(tools);
            Volatile.Write(ref _toolsCachedAtTimestamp, Stopwatch.GetTimestamp());
            _lastToolFetchFailed = false;
            logger.LogInformation("MCP tool cache refreshed: {ToolCount} tools from {McpUrl}", tools.Count, config.McpUrl);
            return tools;
        }
        catch
        {
            Volatile.Write(ref _toolsCachedAtTimestamp, Stopwatch.GetTimestamp());
            _lastToolFetchFailed = true;
            _toolCache = null;
            throw;
        }
        finally
        {
            _toolCacheLock.Release();
        }
    }

    private static bool IsStrippedRole(string? role) =>
        string.Equals(role, "system", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(role, "thinking", StringComparison.OrdinalIgnoreCase);
}

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

            var transport = new ModelContextProtocol.Client.HttpClientTransport(new HttpClientTransportOptions
            {
                Endpoint = new Uri(config.McpUrl),
                Name = "mcp",
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

    public async Task InvalidateClientAsync(CancellationToken ct = default)
    {
        await _lock.WaitAsync(ct);
        try
        {
            var old = _client;
            _client = null;
            if (old is not null)
            {
                try { await old.DisposeAsync(); }
                catch { }
            }
        }
        finally
        {
            _lock.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        var old = Interlocked.Exchange(ref _client, null);
        if (old is not null)
            await old.DisposeAsync();
    }
}

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
                ChatCompletionsClient inferenceClient;
                if (config.IsProjectEndpoint)
                {
                    // Azure AI Foundry project endpoint ({host}/models): requires Bearer token with
                    // https://ai.azure.com/.default scope. We add an explicit BearerTokenAuthenticationPolicy
                    // so the correct scope is always used regardless of SDK defaults.
                    // DefaultAzureCredential tries Azure CLI, Visual Studio, managed identity, etc.
                    var aadCredential = new DefaultAzureCredential();
                    var opts = new AzureAIInferenceClientOptions();
                    opts.AddPolicy(
                        new BearerTokenAuthenticationPolicy(aadCredential, "https://ai.azure.com/.default"),
                        HttpPipelinePosition.PerRetry);
                    inferenceClient = new ChatCompletionsClient(
                        new Uri(config.FoundryEndpoint),
                        new AzureKeyCredential(config.FoundryKey),
                        opts);
                }
                else
                {
                    // Standard Azure AI Inference or Azure OpenAI endpoint: use API key.
                    inferenceClient = new ChatCompletionsClient(new Uri(config.FoundryEndpoint), new AzureKeyCredential(config.FoundryKey));
                }

                IChatClient client = inferenceClient.AsIChatClient(config.FoundryModel);
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
