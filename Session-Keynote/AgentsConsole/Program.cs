using System.ClientModel;
using Microsoft.Extensions.AI;
using ModelContextProtocol.Client;
using OpenAI;
using Spectre.Console;

var mcpUrl = Environment.GetEnvironmentVariable("DAB_MCP_ENDPOINT")
    ?? throw new InvalidOperationException("DAB_MCP_ENDPOINT is not set.");
var endpoint = Environment.GetEnvironmentVariable("FOUNDRY_ENDPOINT")
    ?? throw new InvalidOperationException("FOUNDRY_ENDPOINT is not set.");
var apiKey = Environment.GetEnvironmentVariable("FOUNDRY_API_KEY")
    ?? throw new InvalidOperationException("FOUNDRY_API_KEY is not set.");
var model = Environment.GetEnvironmentVariable("FOUNDRY_MODEL") ?? "gpt-4o-mini";

var openAI = new OpenAIClient(new ApiKeyCredential(apiKey), new OpenAIClientOptions { Endpoint = new Uri(endpoint) });

IChatClient chatClient = new ChatClientBuilder(openAI.GetChatClient(model).AsIChatClient())
    .UseFunctionInvocation()
    .Build();

var transport = new HttpClientTransport(new HttpClientTransportOptions
{
    Endpoint = new Uri(mcpUrl),
    Name = "dab-mcp",
    TransportMode = HttpTransportMode.StreamableHttp
});
var mcpClient = await McpClient.CreateAsync(transport);
var tools = await mcpClient.ListToolsAsync();

var dataAgentPrompt = """
    You are a database specialist. Your only job is to query the product database
    and return raw, structured data that answers the user's business question.

    You have access to three MCP tools:
      - Category: product categories (CategoryId, Name)
      - Product: product catalog (ProductId, Name, CategoryId, Price, Cost, Inventory)
      - SalesHistory: transaction records (ProductId, SaleDate, UnitsSold, UnitPrice, ReturnFlag). Last 24 months. 1=returned.

    When given a business question, identify what data is needed to answer it,
    call the appropriate tools, and return the results as a structured summary.

    Rules:
      - Always join Products with SalesHistory when evaluating performance.
      - Always include: total units sold, total revenue, return rate, and current inventory for each product you return.
      - Return data for ALL products so the analyst can compare, not just candidates you suspect.
      - Do not interpret or recommend. Return data only.
      - Format your response as a clear data table or structured list.
    """;

var analystPrompt = """
    You are a business analyst. You receive product performance data and produce
    a single, clear business recommendation.

    You have no database access. You reason only from the data given to you.

    Your job for this demo is to answer: which product should we consider
    discontinuing, and why?

    Rules:
      - Pick exactly one product. Be decisive.
      - Base your recommendation on at least two signals from the data
        (e.g. low sales volume + high return rate, or declining trend + low margin).
      - State your recommendation in the first sentence.
      - Follow with 2-3 supporting data points. Be specific with numbers.
      - Keep your total response under 150 words.
      - Do not hedge. Do not say "it depends." Make the call.
    """;

AnsiConsole.Write(new Panel("[bold]Multi-Agent Product Intelligence[/]\nType a question and press Enter. Type [grey]exit[/] to quit.")
    .Border(BoxBorder.Double).BorderColor(Color.Blue));

while (true)
{
    var question = AnsiConsole.Ask<string>("[green]You:[/]");
    if (question.Equals("exit", StringComparison.OrdinalIgnoreCase)) break;

    string dataResponse = "";
    await AnsiConsole.Status().StartAsync("Data Agent querying...", async ctx =>
    {
        var messages = new List<ChatMessage>
        {
            new(ChatRole.System, dataAgentPrompt),
            new(ChatRole.User, question)
        };
        var response = await chatClient.GetResponseAsync(messages, new ChatOptions { Tools = [.. tools] });
        dataResponse = response.Messages
            .Where(m => m.Role == ChatRole.Assistant && !string.IsNullOrWhiteSpace(m.Text))
            .Select(m => m.Text)
            .LastOrDefault() ?? "(no data returned)";
    });

    AnsiConsole.Write(new Panel(dataResponse).Header("[yellow]Data Agent[/]").Border(BoxBorder.Rounded).BorderColor(Color.Yellow));

    string recommendation = "";
    await AnsiConsole.Status().StartAsync("Analyst Agent evaluating...", async ctx =>
    {
        var messages = new List<ChatMessage>
        {
            new(ChatRole.System, analystPrompt),
            new(ChatRole.User, $"Question: {question}\n\nData:\n{dataResponse}")
        };
        var response = await chatClient.GetResponseAsync(messages);
        recommendation = response.Messages
            .Where(m => m.Role == ChatRole.Assistant && !string.IsNullOrWhiteSpace(m.Text))
            .Select(m => m.Text)
            .LastOrDefault() ?? "(no recommendation)";
    });

    AnsiConsole.Write(new Panel(recommendation).Header("[bold red]Recommendation[/]").Border(BoxBorder.Heavy).BorderColor(Color.Red));
    AnsiConsole.WriteLine();
}

await mcpClient.DisposeAsync();
