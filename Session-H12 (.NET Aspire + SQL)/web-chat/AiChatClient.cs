using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.ClientModel;
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Extensions.AI;
using OpenAI;
using ModelContextProtocol.Client;
using ChatRole = Microsoft.Extensions.AI.ChatRole;
using ChatMessage = Microsoft.Extensions.AI.ChatMessage;

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

public sealed class AiChatClient(IChatClient? chatClient, McpClientFactory mcpFactory, IHttpClientFactory httpFactory, IHostEnvironment env, ILogger<AiChatClient> logger, AiChatConfig config, ProjectEndpointTokenProvider? tokenProvider = null, ILoggerFactory? loggerFactory = null)
{
    private readonly bool _isDevelopment = env.IsDevelopment();
    private readonly TimeSpan _toolCacheTtl = TimeSpan.FromMinutes(config.ToolCacheTtlMinutes);
    private readonly TimeSpan _toolCacheFailTtl = TimeSpan.FromSeconds(config.ToolCacheFailTtlSeconds);

    private readonly SemaphoreSlim _toolCacheLock = new(1, 1);
    private sealed record ToolCacheEntry(IReadOnlyList<McpClientTool> Tools);
    private volatile ToolCacheEntry? _toolCache;
    private long _toolsCachedAtTimestamp;
    private volatile bool _lastToolFetchFailed;

    // For project endpoints: lazily built client using AzureOpenAIClient (handles token refresh internally)
    private volatile IChatClient? _projectClient;

    private static readonly string DefaultSystemPrompt =
        """
        You are a helpful assistant with access to database tools.
        Use the available tools to query the database when users ask about products, categories, inventory, or warehouses.
        Always use tools to get real data — never make up answers.

        Response rules:
        - Your audience is a human, not a developer. Every reply must be plain, readable language.
        - Use markdown formatting: **bold** for emphasis, tables for tabular data, bullet lists for multiple items.
        - When listing records (products, inventory, etc.), prefer a markdown table with clear column headers.
        - Never show JSON, tool names, parameter names, raw payloads, or technical IDs in your reply.
        - Never narrate your process. Do not say "calling", "attempting", "querying", or "updating" — just do it and state the result.
        - Keep answers to one or two short sentences unless the data warrants a table or list.
        - Do not ask follow-up questions unless the user's request was genuinely ambiguous.

        Tool usage rules:
        - When updating a record, include all required fields (read the record first if needed).
        - Always complete multi-step operations fully. If you read a record before updating, immediately proceed to the update — never stop after the read.
        - When a tool returns an error, explain the problem in plain language — do not echo the error payload.
        """;

    private readonly string _systemPrompt = config.SystemPrompt ?? DefaultSystemPrompt;

    public AiChatConfig Config => config;

    public async Task<ChatResult> ChatAsync(ChatRequest request, CancellationToken ct = default)
    {
        if (request.Messages is null || request.Messages.Count == 0)
            return new ChatResult("No messages provided in request.", error: true, statusCode: 400);

        var strippedCount = request.Messages.Count(m => IsStrippedRole(m.Role));
        if (strippedCount > 0)
            logger.LogWarning("Stripped {Count} non-conversation message(s) (system/thinking) from request", strippedCount);

        var userMessages = request.Messages
            .Where(m => !IsStrippedRole(m.Role))
            .ToList();

        if (userMessages.Count > config.MaxMessages)
            return new ChatResult(
                $"Conversation too long ({userMessages.Count} messages). " +
                $"Maximum is {config.MaxMessages}. Start a new conversation.",
                error: true, statusCode: 400);

        var totalChars = 0;
        foreach (var m in userMessages)
        {
            var len = m.Content?.Length ?? 0;
            if (len > config.MaxMessageChars)
                return new ChatResult(
                    $"A single message is too large ({len:N0} chars, max {config.MaxMessageChars:N0}). " +
                    $"Shorten it and try again.",
                    error: true, statusCode: 400);
            totalChars += len;
        }

        if (totalChars > config.MaxTotalChars)
            return new ChatResult(
                $"Conversation exceeds char budget (~{totalChars:N0} chars, max {config.MaxTotalChars:N0}). " +
                $"Start a new conversation.",
                error: true, statusCode: 400);

        IReadOnlyList<McpClientTool> tools;
        try
        {
            var toolSw = System.Diagnostics.Stopwatch.StartNew();
            tools = await GetToolsCachedAsync(ct);
            toolSw.Stop();
            if (toolSw.ElapsedMilliseconds > 100)
            {
                logger.LogWarning("Tool fetch took {ElapsedMs}ms (from cache: {Cached})", 
                    toolSw.ElapsedMilliseconds, _toolCache is not null);
            }
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "MCP tool fetch failed for {McpUrl}", config.McpUrl);
            await mcpFactory.InvalidateClientAsync();
            return new ChatResult(
                $"Cannot reach MCP server at {config.McpUrl}. Is it running?",
                error: true, statusCode: 502,
                details: _isDevelopment ? $"{ex.GetType().Name}: {ex.Message}" : null);
        }

        var messages = new List<ChatMessage> { new(ChatRole.System, _systemPrompt) };

        foreach (var msg in userMessages)
        {
            if (string.IsNullOrWhiteSpace(msg.Role))
                return new ChatResult("Message has empty role.", error: true, statusCode: 400);

            var role = msg.Role switch
            {
                var r when r.Equals("user", StringComparison.OrdinalIgnoreCase) => ChatRole.User,
                var r when r.Equals("assistant", StringComparison.OrdinalIgnoreCase) => ChatRole.Assistant,
                _ => (ChatRole?)null
            };

            if (role is null)
                return new ChatResult($"Unrecognized message role: '{msg.Role}'. Expected 'user' or 'assistant'.", error: true, statusCode: 400);

            messages.Add(new ChatMessage(role.Value, msg.Content ?? ""));
        }

        var chatOptions = new ChatOptions { Tools = [.. tools] };

        // Get the active client (may refresh for project endpoints)
        var activeClient = await GetActiveChatClientAsync(ct);

        try
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            logger.LogInformation("Starting chat request with {ToolCount} tools available", tools.Count);
            
            var response = await activeClient.GetResponseAsync(messages, chatOptions, ct);
            
            sw.Stop();
            logger.LogInformation("Chat request completed in {ElapsedMs}ms (FinishReason={FinishReason}, Messages={MessageCount})",
                sw.ElapsedMilliseconds, response.FinishReason?.ToString() ?? "null", response.Messages.Count);

            // Token-limit truncation: the model ran out of output tokens mid-response.
            // This can cause tool-calling to abort, leaving the user with partial narration.
            if (response.FinishReason == ChatFinishReason.Length)
            {
                logger.LogWarning("Response truncated — FinishReason=Length. The model hit its output token limit.");
                return new ChatResult(
                    "The model's response was cut short (output token limit reached). " +
                    "Try a shorter conversation or a simpler question.");
            }

            // Use only the last assistant message's text — this skips intermediate
            // narration the model emits between tool-calling rounds (e.g. "I'll read
            // the record first...") and gives just the final human-facing answer.
            var lastAssistantText = response.Messages
                .Where(m => m.Role == ChatRole.Assistant && !string.IsNullOrWhiteSpace(m.Text))
                .Select(m => m.Text)
                .LastOrDefault();

            var answer = string.IsNullOrWhiteSpace(lastAssistantText)
                ? "(Model returned only tool calls — no final answer generated. Try rephrasing your question.)"
                : SanitizeToolCallArtifacts(lastAssistantText);
            return new ChatResult(answer);
        }
        catch (ClientResultException ex)
        {
            logger.LogError(ex, "AI model error: HTTP {Status} from {Endpoint}/{Model}", ex.Status, config.FoundryEndpoint, config.FoundryModel);
            var keyHint = ex.Status is 401 or 403
                ? " Likely cause: the API key is wrong. Check FOUNDRY_KEY."
                : "";
            return new ChatResult(
                $"The model at {config.FoundryEndpoint} returned HTTP {ex.Status}. Model: {config.FoundryModel}.{keyHint}",
                error: true, statusCode: 502,
                details: _isDevelopment ? $"{ex.GetType().Name}: {ex.Message}" : null);
        }
        catch (HttpRequestException ex)
        {
            logger.LogError(ex, "Network error reaching AI endpoint {Endpoint}", config.FoundryEndpoint);
            return new ChatResult(
                $"Cannot reach AI endpoint {config.FoundryEndpoint}.",
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
                $"The AI model did not respond in time. Endpoint: {config.FoundryEndpoint}, Model: {config.FoundryModel}",
                error: true, statusCode: 504,
                details: _isDevelopment ? ex.Message : null);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error in ChatAsync");
            return new ChatResult(
                "An internal error occurred.",
                error: true, statusCode: 500,
                details: _isDevelopment ? $"{ex.GetType().Name}: {ex.Message}" : null,
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

            if (config.IsProjectEndpoint && tokenProvider is not null)
            {
                // For Azure AI Foundry project endpoints, reuse the injected token provider
                // (which caches tokens) rather than creating a fresh DefaultAzureCredential.
                try
                {
                    var token = await tokenProvider.GetTokenAsync(ct);
                    if (string.IsNullOrWhiteSpace(token))
                        issues.Add("DefaultAzureCredential returned an empty token. Ensure Azure CLI is logged in or a managed identity is configured.");
                    // Connectivity check: HEAD the base models inference URL
                    using var headReq = new HttpRequestMessage(HttpMethod.Head,
                        config.FoundryEndpoint.TrimEnd('/') + "/chat/completions");
                    headReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
                    // HEAD may return 405 (method not allowed) which still means the server is reachable.
                    var headResp = await http.SendAsync(headReq, ct);
                    if ((int)headResp.StatusCode is 0 or >= 500)
                        issues.Add($"AI Foundry endpoint connectivity check failed (HTTP {(int)headResp.StatusCode}) at '{config.FoundryEndpoint}'.");
                }
                catch (Exception tokenEx)
                {
                    issues.Add($"Token provider error: {tokenEx.GetType().Name} — {tokenEx.Message}");
                }
            }
            else
            {
                // Lightweight connectivity check — HEAD the chat completions endpoint
                // with the API key. Avoids creating a new OpenAIClient and running a
                // full completion (which costs tokens and latency) on every health probe.
                try
                {
                    var probeUrl = $"{config.FoundryEndpoint.TrimEnd('/')}/openai/deployments/{Uri.EscapeDataString(config.FoundryModel)}/chat/completions?api-version=2024-06-01";
                    using var req = new HttpRequestMessage(HttpMethod.Head, probeUrl);
                    req.Headers.Add("api-key", config.FoundryKey);
                    var resp = await http.SendAsync(req, ct);
                    // 405 (method not allowed) means the endpoint is reachable and the key is valid.
                    if (resp.StatusCode is System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden)
                        issues.Add($"Azure OpenAI returned {(int)resp.StatusCode}. Check that FOUNDRY_KEY is correct.");
                    else if (resp.StatusCode is System.Net.HttpStatusCode.NotFound)
                        issues.Add($"Deployment '{config.FoundryModel}' not found at '{config.FoundryEndpoint}'.");
                    else if ((int)resp.StatusCode >= 500)
                        issues.Add($"Azure OpenAI endpoint returned {(int)resp.StatusCode} at '{config.FoundryEndpoint}'.");
                }
                catch (HttpRequestException ex)
                {
                    issues.Add($"Azure OpenAI endpoint unreachable: {ex.Message}");
                }
            }
        }
        catch (Exception ex)
        {
            issues.Add($"AI endpoint unreachable at '{config.FoundryEndpoint}': {ex.GetType().Name} — {ex.Message}");
        }

        return new HealthResult(
            status: issues.Count == 0 ? "healthy" : "unhealthy",
            config: new HealthConfig(config.FoundryEndpoint, config.FoundryModel, config.MaskedKey, config.McpUrl),
            issues: issues
        );
    }

    // Strips raw JSON tool-call payloads, MCP response envelopes, and cursor
    // metadata that the model sometimes emits verbatim in its text response.
    private static readonly Regex ToolCallJsonPattern = new(
        @"^\s*\{[\s\S]*?(""entity""|""keys""|""fields""|""toolName""|""cursor""|""isError""|""type""\s*:\s*""response""|""status""\s*:\s*""success""|""result""\s*:\s*\{)[\s\S]*?\}\s*$",
        RegexOptions.Multiline | RegexOptions.Compiled,
        TimeSpan.FromMilliseconds(50));

    private static readonly Regex MultiLineJsonBlock = new(
        @"^\s*\{[\s\S]*?\}\s*$",
        RegexOptions.Multiline | RegexOptions.Compiled,
        TimeSpan.FromMilliseconds(50));

    private static readonly Regex NarrationPattern = new(
        @"^.*(?:The\s+create_record\s+call|resending\s+correctly|How\s+to\s+interpret|had\s+to\s+be\s+sent\s+as).*$",
        RegexOptions.Multiline | RegexOptions.IgnoreCase | RegexOptions.Compiled,
        TimeSpan.FromMilliseconds(50));

    private static string SanitizeToolCallArtifacts(string text)
    {
        try
        {
            // Remove lines that are raw JSON with tool-call keys
            text = ToolCallJsonPattern.Replace(text, "");
            // Remove narration about tool call mechanics
            text = NarrationPattern.Replace(text, "");
            // Collapse leftover blank lines
            text = Regex.Replace(text, @"\n{3,}", "\n\n").Trim();
        }
        catch (RegexMatchTimeoutException)
        {
            // If regex times out on adversarial input, return text as-is
        }
        return text;
    }

    private async Task<IReadOnlyList<McpClientTool>> GetToolsCachedAsync(CancellationToken ct = default)
    {
        // Capture consistent snapshot of cache state before lock to avoid TOCTOU races
        var cache = _toolCache;
        var lastFetchFailed = _lastToolFetchFailed;
        var cachedAt = Volatile.Read(ref _toolsCachedAtTimestamp);
        var now = Stopwatch.GetTimestamp();
        var ttl = lastFetchFailed ? _toolCacheFailTtl : _toolCacheTtl;

        if (cache is not null && Stopwatch.GetElapsedTime(cachedAt, now) < ttl)
            return cache.Tools;

        if (lastFetchFailed && cache is null && Stopwatch.GetElapsedTime(cachedAt, now) < _toolCacheFailTtl)
            throw new InvalidOperationException($"MCP tool fetch recently failed; retrying after {config.ToolCacheFailTtlSeconds}s cooldown.");

        await _toolCacheLock.WaitAsync(ct);
        try
        {
            // Re-check with fresh snapshot inside lock
            cache = _toolCache;
            lastFetchFailed = _lastToolFetchFailed;
            cachedAt = Volatile.Read(ref _toolsCachedAtTimestamp);
            now = Stopwatch.GetTimestamp();
            ttl = lastFetchFailed ? _toolCacheFailTtl : _toolCacheTtl;
            
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

    /// <summary>
    /// Gets the active IChatClient, lazily building it for project endpoints.
    /// </summary>
    private Task<IChatClient> GetActiveChatClientAsync(CancellationToken ct = default)
    {
        // For non-project endpoints, use the injected singleton client
        if (tokenProvider is null)
            return Task.FromResult(chatClient ?? throw new InvalidOperationException("No IChatClient configured for API key endpoint"));

        // For project endpoints, lazily build the client once.
        // AzureOpenAIClient handles token refresh internally via TokenCredential.
        var client = _projectClient;
        if (client is not null)
            return Task.FromResult(client);

        return BuildProjectClientAsync();
    }

    private Task<IChatClient> BuildProjectClientAsync()
    {
        var azureClient = new AzureOpenAIClient(
            new Uri(config.FoundryEndpoint),
            tokenProvider!.Credential);

        var rawChatClient = azureClient.GetChatClient(config.FoundryModel);
        IChatClient wrappedClient = rawChatClient.AsIChatClient();

        if (loggerFactory is not null)
        {
            wrappedClient = new ChatClientBuilder(wrappedClient)
                .UseLogging(loggerFactory)
                .UseFunctionInvocation(configure: options =>
                {
                    options.MaximumIterationsPerRequest = 10;
                })
                .Build();
        }

        _projectClient = wrappedClient;
        logger.LogInformation("Built AzureOpenAIClient for project endpoint (token refresh handled by SDK)");
        return Task.FromResult(wrappedClient);
    }
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

/// <summary>
/// Provides auto-refreshing Azure tokens for project endpoints.
/// Tokens expire after ~1 hour; this provider caches and refreshes them transparently.
/// </summary>
public sealed class ProjectEndpointTokenProvider
{
    private readonly Azure.Core.TokenCredential _credential;
    private readonly string[] _scopes;
    private Azure.Core.AccessToken _cachedToken;
    private readonly SemaphoreSlim _lock = new(1, 1);

    /// <summary>The underlying credential, for passing to AzureOpenAIClient.</summary>
    public Azure.Core.TokenCredential Credential => _credential;

    public ProjectEndpointTokenProvider(Azure.Core.TokenCredential credential, string[] scopes)
    {
        _credential = credential;
        _scopes = scopes;
    }

    public async Task<string> GetTokenAsync(CancellationToken cancellationToken = default)
    {
        // Refresh token if expired or not yet fetched (with 5 minute buffer for safety)
        var now = DateTimeOffset.UtcNow;
        if (_cachedToken.Token == null || _cachedToken.ExpiresOn < now.AddMinutes(5))
        {
            await _lock.WaitAsync(cancellationToken);
            try
            {
                // Double-check after acquiring lock with fresh timestamp
                now = DateTimeOffset.UtcNow;
                if (_cachedToken.Token == null || _cachedToken.ExpiresOn < now.AddMinutes(5))
                {
                    var tokenContext = new Azure.Core.TokenRequestContext(_scopes);
                    _cachedToken = await _credential.GetTokenAsync(tokenContext, cancellationToken);
                }
            }
            finally
            {
                _lock.Release();
            }
        }

        return _cachedToken.Token!;
    }
}

public static class AiChatServiceExtensions
{
    public static IServiceCollection AddAiChatClient(this IServiceCollection services, AiChatConfig config)
    {
        services.AddSingleton(config);
        services.AddHttpClient();

        services.AddSingleton<McpClientFactory>();

        if (config.IsProjectEndpoint)
        {
            // For Azure AI Foundry project endpoints, inject token provider
            // AiChatClient will rebuild the client when tokens are stale
            services.AddSingleton(sp => new ProjectEndpointTokenProvider(
                new DefaultAzureCredential(),
                ["https://ai.azure.com/.default"]));

            services.AddSingleton<AiChatClient>(sp =>
            {
                var tokenProvider = sp.GetRequiredService<ProjectEndpointTokenProvider>();
                var loggerFactory = sp.GetRequiredService<ILoggerFactory>();
                return new AiChatClient(
                    chatClient: null, // Will be built on-demand
                    sp.GetRequiredService<McpClientFactory>(),
                    sp.GetRequiredService<IHttpClientFactory>(),
                    sp.GetRequiredService<IHostEnvironment>(),
                    sp.GetRequiredService<ILogger<AiChatClient>>(),
                    config,
                    tokenProvider,
                    loggerFactory);
            });
        }
        else
        {
            // For API key endpoints, create singleton client (keys don't expire)
            services.AddSingleton<IChatClient>(sp =>
            {
                try
                {
                    var openAIClient = new OpenAIClient(
                        new ApiKeyCredential(config.FoundryKey),
                        new OpenAIClientOptions
                        {
                            Endpoint = new Uri(config.FoundryEndpoint)
                        });

                    var chatClient = openAIClient.GetChatClient(config.FoundryModel);

                    // Wrap with Microsoft.Extensions.AI and add middleware
                    IChatClient client = chatClient.AsIChatClient();
                    var loggerFactory = sp.GetRequiredService<ILoggerFactory>();
                    return new ChatClientBuilder(client)
                        .UseLogging(loggerFactory)
                        .UseFunctionInvocation(configure: options =>
                        {
                            options.MaximumIterationsPerRequest = 10;  // Cap tool invocation rounds
                        })
                        .Build();
                }
                catch (Exception ex)
                {
                    throw new InvalidOperationException(
                        $"Failed to create OpenAI chat client. Endpoint='{config.FoundryEndpoint}', Model='{config.FoundryModel}'. " +
                        $"({ex.GetType().Name}: {ex.Message})", ex);
                }
            });

            services.AddSingleton<AiChatClient>();
        }

        return services;
    }
}
