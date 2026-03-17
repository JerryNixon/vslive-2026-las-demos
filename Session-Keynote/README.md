# Session Keynote — Multi-Agent Product Intelligence

Two-agent demo: a **Data Agent** queries product/sales data via DAB MCP, then a **Business Analyst Agent** recommends which product to discontinue.

## Prerequisites

- Docker Desktop
- .NET 10 SDK
- Aspire CLI (`dotnet tool install -g aspire.cli`)
- An Azure OpenAI deployment (gpt-4o-mini recommended)

## Setup

1. Edit `AgentsConsole/Properties/launchSettings.json` and set your Foundry credentials:
   - `FOUNDRY_ENDPOINT` — your Azure OpenAI endpoint
   - `FOUNDRY_API_KEY` — your API key
   - `FOUNDRY_MODEL` — deployment name (default: `gpt-4o-mini`)

2. Run:
   ```
   aspire run
   ```

3. In the console, type:
   ```
   What product should we consider discontinuing, and why?
   ```

## Architecture

```
AgentsConsole ──► DAB MCP (port 8012) ──► SQL Server (port 8011)
     │                                         │
     │                                    AgentsDb
     ▼                                  (Category, Product,
  Azure OpenAI                          SalesHistory)
  (gpt-4o-mini)
```

- **Data Agent** — has MCP tools, queries all products + sales, returns raw data
- **Analyst Agent** — no tools, receives the data, makes a recommendation
- **DAB** — MCP-only (REST/GraphQL disabled), read-only, anonymous access
