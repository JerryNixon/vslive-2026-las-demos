using System.ClientModel;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.Sql;
using Microsoft.Extensions.Logging;
using OpenAI;
using OpenAI.Embeddings;

namespace EmbedFunction;

public class EmbedOnChange
{
    private readonly ILogger<EmbedOnChange> _logger;

    public EmbedOnChange(ILogger<EmbedOnChange> logger)
    {
        _logger = logger;
    }

    // Fires when change tracking detects new/updated rows in ReviewVector
    [Function("EmbedOnChange")]
    public void Run(
        [SqlTrigger("[dbo].[ReviewVector]", "SqlConnection")]
        IReadOnlyList<SqlChange<ReviewVectorRow>> changes)
    {
        var endpoint = Environment.GetEnvironmentVariable("OpenAI__Endpoint")
            ?? throw new InvalidOperationException("OpenAI__Endpoint not set");
        var apiKey = Environment.GetEnvironmentVariable("OpenAI__ApiKey")
            ?? throw new InvalidOperationException("OpenAI__ApiKey not set");
        var deployment = Environment.GetEnvironmentVariable("OpenAI__Deployment") ?? "text-embedding-3-large";
        var connStr = Environment.GetEnvironmentVariable("SqlConnection")
            ?? throw new InvalidOperationException("SqlConnection not set");

        var client = new EmbeddingClient(
            deployment,
            new ApiKeyCredential(apiKey),
            new OpenAIClientOptions { Endpoint = new Uri(endpoint) });

        foreach (var change in changes)
        {
            var row = change.Item;

            if (string.IsNullOrWhiteSpace(row.Chunk) || row.Embedding != null)
                continue;

            _logger.LogInformation("Embedding ReviewVector Id={Id}", row.Id);

            OpenAIEmbedding embedding = client.GenerateEmbedding(row.Chunk);
            ReadOnlyMemory<float> vector = embedding.ToFloats();

            // Write the vector back to SQL as a JSON array string
            var vectorJson = "[" + string.Join(",", vector.ToArray()) + "]";

            using var conn = new Microsoft.Data.SqlClient.SqlConnection(connStr);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "UPDATE dbo.ReviewVector SET Embedding = CAST(@v AS VECTOR(1536)) WHERE Id = @id";
            cmd.Parameters.AddWithValue("@id", row.Id);
            cmd.Parameters.AddWithValue("@v", vectorJson);
            cmd.ExecuteNonQuery();

            _logger.LogInformation("Embedded ReviewVector Id={Id} ({Dims} dimensions)", row.Id, vector.Length);
        }
    }
}

public class ReviewVectorRow
{
    public int Id { get; set; }
    public int ReviewId { get; set; }
    public string? Chunk { get; set; }
    public string? Embedding { get; set; }
}
