using System.Net.Http.Json;

var builder = WebApplication.CreateBuilder(args);

var dabUrl = Environment.GetEnvironmentVariable("services__data-api__http__0")
    ?? Environment.GetEnvironmentVariable("services__data-api__https__0")
    ?? "http://localhost:4567";

builder.Services.AddHttpClient("dab", c => c.BaseAddress = new Uri(dabUrl));

var app = builder.Build();

app.MapGet("/", async (IHttpClientFactory factory) =>
{
    var http = factory.CreateClient("dab");
    var warehouses = (await http.GetFromJsonAsync<DabResponse<Warehouse>>("/api/Warehouse"))?.Value ?? [];
    var products = (await http.GetFromJsonAsync<DabResponse<Product>>("/api/Product"))?.Value ?? [];
    var productNames = products.ToDictionary(p => p.ProductId, p => p.Name);

    var accordionItems = "";
    foreach (var w in warehouses)
    {
        var inventory = (await http.GetFromJsonAsync<DabResponse<Inventory>>(
            $"/api/Inventory?$filter=WarehouseId eq {w.WarehouseId}"))?.Value ?? [];

        var rows = string.Join("\n", inventory.Select(i =>
            $"<tr><td>{productNames.GetValueOrDefault(i.ProductId, $"Product {i.ProductId}")}</td><td>{i.Quantity}</td></tr>"));

        var body = inventory.Length == 0
            ? "<p class=\"text-muted\">No inventory at this warehouse.</p>"
            : $"""
               <table class="table table-sm table-striped mb-0">
                 <thead><tr><th>Product</th><th>Quantity</th></tr></thead>
                 <tbody>{rows}</tbody>
               </table>
               """;

        accordionItems += $"""
            <div class="accordion-item">
              <h2 class="accordion-header" id="h-{w.WarehouseId}">
                <button class="accordion-button collapsed" type="button"
                        data-bs-toggle="collapse" data-bs-target="#c-{w.WarehouseId}">
                  <strong>{w.Name}</strong>
                  <span class="text-muted ms-2">— {w.Location}</span>
                </button>
              </h2>
              <div id="c-{w.WarehouseId}" class="accordion-collapse collapse" data-bs-parent="#acc">
                <div class="accordion-body">{body}</div>
              </div>
            </div>
            """;
    }

    var html = $"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>Warehouse Summary</title>
          <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet" />
        </head>
        <body>
          <nav class="navbar navbar-dark bg-dark mb-3">
            <div class="container">
              <a class="navbar-brand" href="/">Warehouse App <span class="badge bg-secondary">ASP.NET</span></a>
            </div>
          </nav>
          <div class="container mt-4">
            <h1 class="mb-4">Warehouse Summary</h1>
            <div class="accordion" id="acc">{accordionItems}</div>
          </div>
          <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
        </body>
        </html>
        """;

    return Results.Content(html, "text/html");
});

app.Run();

record DabResponse<T>(T[] Value);
record Warehouse(int WarehouseId, string Name, string Location);
record Product(int ProductId, string Name);
record Inventory(int InventoryId, int ProductId, int WarehouseId, int Quantity);
