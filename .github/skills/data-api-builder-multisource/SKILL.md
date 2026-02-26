---
name: data-api-builder-multisource
description: Configure Data API Builder to serve multiple databases from a single instance using data-source-files. Use when asked to connect DAB to more than one database, split config across files, or set up multi-source APIs.
license: MIT
---

# Data API Builder Multi-Source Configuration

This skill provides expert guidance for running **multiple databases through a single Data API Builder (DAB) instance** using the `data-source-files` feature. One DAB process serves REST, GraphQL, and MCP endpoints across all connected databases.

---

## Core Mental Model

- **One parent config** — contains `runtime`, `data-source-files`, and optionally `entities`
- **One child config per database** — contains `data-source`, `entities`, and nothing else that matters
- **One unified API surface** — all entities from all files merge into a single REST + GraphQL + MCP namespace
- **No code** — this is pure JSON configuration; DAB handles the runtime merge

### How It Works

```
┌─────────────────────┐
│  dab-config.json    │  ← parent: runtime + data-source-files
│  (top-level)        │
├─────────────────────┤
│  data-source-files: │
│    - catalog.json   │──→ CatalogDb (SQL Server)
│    - inventory.json │──→ InventoryDb (SQL Server)
│    - recs.json      │──→ RecsDb (Cosmos DB)
└─────────────────────┘
         │
         ▼
   Single DAB instance
   REST + GraphQL + MCP
```

---

## Rules

### Parent Config Rules

1. **`runtime` lives ONLY in the parent** — child `runtime` sections are ignored (with a warning log)
2. **`data-source` in the parent is optional** — if present, it serves as the default connection
3. **`entities` in the parent is mandatory** — DAB 1.7+ requires the `entities` property to exist, even if empty (`"entities": {}`)
4. **`data-source-files` is an array of relative paths** — paths resolve relative to the parent config's location

### Child Config Rules

1. **Every child MUST have both `data-source` and `entities`** — missing either causes a startup failure
2. **Child `runtime` is ignored** — only the parent's runtime settings apply
3. **Entity names must be globally unique** — duplicates across any files cause a fatal startup error
4. **GraphQL type names must be globally unique** — same rule as entity names
5. **REST paths must be globally unique** — no two entities can share a REST route
6. **Relationships cannot cross config files** — an entity in `catalog.json` cannot have a relationship to an entity in `inventory.json`
7. **No circular file references** — `A → B → A` is not allowed

### Environment Variable Rules

1. **Every `@env()` reference must resolve** — a missing env var is a fatal deserialization error, not a warning
2. **Aspire auto-injects `OTEL_SERVICE_NAME` and `OTEL_EXPORTER_OTLP_ENDPOINT`** — but NOT `OTEL_EXPORTER_OTLP_HEADERS`
3. **Never use `@env()` for variables your orchestrator doesn't provide** — DAB treats every `@env()` as mandatory

---

## Templates

### Parent Config (`dab-config.json`)

```json
{
  "$schema": "https://github.com/Azure/data-api-builder/releases/latest/download/dab.draft.schema.json",
  "data-source": {
    "database-type": "mssql",
    "connection-string": "@env('DEFAULT_CONNECTION_STRING')"
  },
  "data-source-files": [
    "dab-config-catalog.json",
    "dab-config-inventory.json"
  ],
  "runtime": {
    "rest": {
      "enabled": true,
      "path": "/api"
    },
    "graphql": {
      "enabled": true,
      "path": "/graphql"
    },
    "host": {
      "mode": "development",
      "cors": {
        "origins": ["*"],
        "allow-credentials": false
      }
    },
    "mcp": {
      "enabled": true
    },
    "telemetry": {
      "open-telemetry": {
        "enabled": true,
        "service-name": "@env('OTEL_SERVICE_NAME')",
        "endpoint": "@env('OTEL_EXPORTER_OTLP_ENDPOINT')",
        "exporter-protocol": "grpc"
      }
    }
  },
  "entities": {}
}
```

> **Critical:** The `"entities": {}` property MUST be present. DAB 1.7+ validates its existence even when all entities are in child files. Omitting it causes: `entities is a mandatory property in DAB Config`.

### Child Config (e.g., `dab-config-catalog.json`)

```json
{
  "data-source": {
    "database-type": "mssql",
    "connection-string": "@env('CATALOG_CONNECTION_STRING')"
  },
  "entities": {
    "Category": {
      "source": "dbo.Categories",
      "rest": true,
      "graphql": true,
      "permissions": [
        {
          "role": "anonymous",
          "actions": ["*"]
        }
      ]
    },
    "Product": {
      "source": "dbo.Products",
      "rest": true,
      "graphql": true,
      "permissions": [
        {
          "role": "anonymous",
          "actions": ["*"]
        }
      ],
      "relationships": {
        "category": {
          "cardinality": "one",
          "target.entity": "Category",
          "source.fields": ["CategoryId"],
          "target.fields": ["CategoryId"]
        }
      }
    }
  }
}
```

### Child Config (e.g., `dab-config-inventory.json`)

```json
{
  "data-source": {
    "database-type": "mssql",
    "connection-string": "@env('INVENTORY_CONNECTION_STRING')"
  },
  "entities": {
    "Warehouse": {
      "source": "dbo.Warehouses",
      "rest": true,
      "graphql": true,
      "permissions": [
        {
          "role": "anonymous",
          "actions": ["*"]
        }
      ]
    },
    "Inventory": {
      "source": "dbo.Inventory",
      "rest": true,
      "graphql": true,
      "permissions": [
        {
          "role": "anonymous",
          "actions": ["*"]
        }
      ],
      "relationships": {
        "warehouse": {
          "cardinality": "one",
          "target.entity": "Warehouse",
          "source.fields": ["WarehouseId"],
          "target.fields": ["WarehouseId"]
        }
      }
    }
  }
}
```

### Mixed Database Types

Multi-source is not limited to SQL Server. You can mix any supported database:

```json
{
  "data-source-files": [
    "dab-config-sql.json",
    "dab-config-cosmos.json"
  ],
  "runtime": { ... },
  "entities": {}
}
```

Where `dab-config-sql.json` uses `"database-type": "mssql"` and `dab-config-cosmos.json` uses `"database-type": "cosmosdb_nosql"`. The API merges them seamlessly.

---

## Aspire Integration

When using multi-source DAB with Aspire, pass all config files to `.WithConfigFile()`:

```csharp
var dabConfig1 = new FileInfo(options.DabConfig);
var dabConfig2 = new FileInfo(options.DabCatalogConfig);
var dabConfig3 = new FileInfo(options.DabInventoryConfig);

var dabServer = builder
    .AddDataAPIBuilder("data-api")
    .WithConfigFile(dabConfig1, dabConfig2, dabConfig3)
    .WithImageTag("1.7.83-rc")
    .WithEnvironment("CATALOG_CONNECTION_STRING", catalogDb)
    .WithEnvironment("INVENTORY_CONNECTION_STRING", inventoryDb)
    .WaitForCompletion(catalogSqlproj)
    .WaitForCompletion(inventorySqlproj);
```

> **Important:** Every `@env()` variable referenced across ALL config files must be provided via `.WithEnvironment()`. Missing any one causes a fatal crash loop.

### Telemetry with Aspire

Aspire auto-injects `OTEL_SERVICE_NAME` and `OTEL_EXPORTER_OTLP_ENDPOINT`. Do NOT add `"headers": "@env('OTEL_EXPORTER_OTLP_HEADERS')"` — Aspire does not inject this variable and DAB will crash.

```json
"telemetry": {
  "open-telemetry": {
    "enabled": true,
    "service-name": "@env('OTEL_SERVICE_NAME')",
    "endpoint": "@env('OTEL_EXPORTER_OTLP_ENDPOINT')",
    "exporter-protocol": "grpc"
  }
}
```

---

## Docker Compose Integration

When using multi-source DAB with Docker Compose, mount all config files:

```yaml
services:
  api-server:
    image: mcr.microsoft.com/azure-databases/data-api-builder:1.7.83-rc
    volumes:
      - ./dab-config.json:/App/dab-config.json:ro
      - ./dab-config-catalog.json:/App/dab-config-catalog.json:ro
      - ./dab-config-inventory.json:/App/dab-config-inventory.json:ro
    environment:
      CATALOG_CONNECTION_STRING: "Server=sql-2025;Database=CatalogDb;User Id=sa;Password=${SA_PASSWORD};TrustServerCertificate=true"
      INVENTORY_CONNECTION_STRING: "Server=sql-2025;Database=InventoryDb;User Id=sa;Password=${SA_PASSWORD};TrustServerCertificate=true"
    ports:
      - "5000:5000"
```

---

## GraphQL Special Behavior

Multi-source GraphQL merges all entities into one schema. A single request can query across databases:

```graphql
{
  products { items { ProductId Name Price } }
  inventories { items { ProductId StockCount Warehouse } }
}
```

Response combines data from separate databases in one payload:

```json
{
  "data": {
    "products": {
      "items": [
        { "ProductId": 1, "Name": "Widget", "Price": 19.99 }
      ]
    },
    "inventories": {
      "items": [
        { "ProductId": 1, "StockCount": 100, "Warehouse": "A" }
      ]
    }
  }
}
```

> **Note:** This is a merged response, not a JOIN. Each entity queries its own database independently. Client-side correlation is required.

---

## MCP with Multi-Source

The same multi-source config feeds DAB's MCP endpoint. Agents (Copilot, Claude, etc.) access all databases through a single MCP surface:

```json
{
  "servers": {
    "my-multi-db": {
      "url": "http://localhost:5000/mcp",
      "type": "http"
    }
  }
}
```

The agent sees tools for every entity across all child configs.

---

## File Organization

### Recommended Layout

```
/data-api
  ├── dab-config.json              # Parent: runtime + data-source-files
  ├── dab-config-catalog.json      # Child: CatalogDb entities
  ├── dab-config-inventory.json    # Child: InventoryDb entities
  └── dab-config-recs.json         # Child: RecsDb entities
```

### Naming Convention

- Parent: `dab-config.json`
- Children: `dab-config-{database-name}.json`

Files can also live in subfolders:

```json
"data-source-files": [
  "configs/catalog.json",
  "configs/inventory.json"
]
```

---

## Troubleshooting

### `entities is a mandatory property in DAB Config`

The parent `dab-config.json` is missing the `entities` property. Add `"entities": {}` even if all entities are in child files. DAB 1.7+ requires it.

### `Environmental Variable, OTEL_EXPORTER_OTLP_HEADERS, not found`

The telemetry config references `@env('OTEL_EXPORTER_OTLP_HEADERS')` but the orchestrator (Aspire/Docker) doesn't provide it. Remove the `headers` field — it's only needed for authenticated OTLP endpoints (cloud APM).

### `Entity name 'X' is already defined`

Two config files define an entity with the same name. Entity names, GraphQL types, and REST paths must be globally unique across ALL config files. Rename one.

### `Relationship target entity 'X' not found`

A relationship references an entity in a different config file. Relationships cannot cross config file boundaries. Both entities must be in the same child config.

### Child config not loading

Verify the path in `data-source-files` is relative to the parent config's location, not the working directory. If DAB runs inside a container, the path must resolve inside the container filesystem (e.g., `/App/dab-config-catalog.json`).

### DAB crash loop on startup

Check container logs for the specific error. The three most common causes:
1. Missing `@env()` variable — every reference must resolve
2. Missing `entities` in parent config
3. Duplicate entity names across files

---

## Reference

- [Multi-Source Docs](https://learn.microsoft.com/en-us/azure/data-api-builder/concept/config/multi-data-source)
- [Multi-Source Blog Post](https://devblogs.microsoft.com/azure-sql/multi-source-data-api-builder/)
- [DAB Configuration Schema](https://github.com/Azure/data-api-builder/blob/main/schemas/dab.draft.schema.json)
- [DAB Documentation](https://aka.ms/dab/docs)
