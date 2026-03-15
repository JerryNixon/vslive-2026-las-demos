# Web Chat Performance Optimization

## Current Performance Issue

The web-chat app shows "Thinking..." for ~40-60 seconds per database query because it makes **multiple roundtrips** to the AI model:

```
User Question → AI Model (20-30s) → Tool Calls → MCP/Database (1-2s) → AI Model Again (20-30s) → Answer
```

## Why It's Slow

1. **.UseFunctionInvocation() middleware** handles tool calling automatically but requires 2+ model calls
2. **Large AI models** (GPT-4, GPT-4o) take 20-30+ seconds per inference
3. **Network latency** to Azure AI endpoint adds overhead
4. **Serial execution** - each step blocks the next

## Solutions (Fastest to Slowest)

### 1. Use a Faster AI Model ⚡ **RECOMMENDED**

Switch from GPT-4 to **gpt-35-turbo** or **gpt-4o-mini**:

**In Aspire Dashboard Parameters:**
- Change `Foundry-Deployment` from `gpt-4` to `gpt-35-turbo`

**Speed gain:** 5-10x faster (3-5 seconds per call vs 20-30 seconds)

GPT-3.5-Turbo is:
- Fast enough for production chat apps
- Accurate for database queries and structured data
- Much cheaper ($0.50/1M tokens vs $30/1M for GPT-4)

### 2. Enable Response Streaming

Modify [AiChatClient.cs](web-chat/AiChatClient.cs) to use streaming:

```csharp
// Replace GetResponseAsync with streaming
await foreach (var update in chatClient.GetStreamingResponseAsync(messages, chatOptions, ct))
{
    if (!string.IsNullOrEmpty(update.Text))
    {
        // Send partial response to client
        yield return update.Text;
    }
}
```

**Speed gain:** User sees first words in ~2-3 seconds (perceived performance)

### 3. Optimize Tool Schemas

Reduce the number of tools or combine related operations:

```json
// Instead of separate get_product and get_category tools
// Use a single query tool with filters
{
  "name": "query_data",
  "description": "Query products, categories, inventory with filters",
  "parameters": {...}
}
```

**Speed gain:** Reduces chance of multiple tool calls (10-20% faster)

### 4. Add Response Caching

Cache common queries in-memory:

```csharp
// In AiChatClient
private readonly MemoryCache _responseCache = new(new MemoryCacheOptions());

// Before calling AI
if (_responseCache.TryGetValue(userQuery, out ChatResult? cached))
    return cached;
```

**Speed gain:** Instant responses for repeated questions

### 5. Use Parallel Tool Execution

If the model returns multiple tool calls, execute them in parallel:

```csharp
var toolResults = await Task.WhenAll(
    toolCalls.Select(tc => ExecuteToolAsync(tc, ct))
);
```

**Speed gain:** 20-40% faster when multiple tools are called

## Quick Win: Switch to GPT-3.5-Turbo NOW

1. Stop Aspire (Ctrl+C in terminal)
2. Restart: `aspire run`
3. When prompted for `Foundry-Deployment`, enter `gpt-35-turbo`
4. Test: "Show me all products" should respond in ~10-15 seconds

## Monitoring Performance

The code now includes timing logs. Check Aspire logs for:

```
Starting chat request with 8 tools available
Chat request completed in 42573ms
```

## References

- [Azure OpenAI Models](https://learn.microsoft.com/azure/ai-services/openai/concepts/models)
- [Microsoft.Extensions.AI Docs](https://devblogs.microsoft.com/dotnet/introducing-microsoft-extensions-ai-preview/)
- [Function Calling Best Practices](https://platform.openai.com/docs/guides/function-calling)
