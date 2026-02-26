---
name: data-api-builder-otel
description: Configure OpenTelemetry tracing and metrics in Data API Builder for Aspire, Docker, and Azure. Use when asked to add OTEL, telemetry, tracing, metrics, or monitoring to DAB.
license: MIT
---

# Data API Builder — OpenTelemetry

Enable distributed tracing and metrics in Data API Builder (DAB) so traces flow to Aspire Dashboard, Jaeger, Azure Monitor, or any OTLP-compatible backend.

---

## Core Mental Model

- DAB uses the **.NET OpenTelemetry SDK** internally — it emits traces and metrics for REST, GraphQL, MCP, and database operations
- Configuration lives in `runtime.telemetry.open-telemetry` inside `dab-config.json`
- Values support `@env('VAR')` syntax — but **every `@env()` reference must resolve at startup or DAB crashes**
- Aspire auto-injects `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_SERVICE_NAME` into containers — no manual wiring needed
- The `headers` field is only needed when the OTLP endpoint requires authentication (cloud APM) — omit it for local dev

---

## Aspire Pitfall: `@env('OTEL_EXPORTER_OTLP_HEADERS')`

**This is the most common telemetry misconfiguration.**

Aspire injects `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_SERVICE_NAME` into every container, but it does **NOT** inject `OTEL_EXPORTER_OTLP_HEADERS`. If your config includes:

```json
"headers": "@env('OTEL_EXPORTER_OTLP_HEADERS')"
```

DAB will enter a **fatal crash loop** because `@env()` references are resolved during JSON deserialization — an unset variable is a hard failure, not an empty string.

**Fix:** Remove the `headers` field entirely for local/Aspire development. Only add it when targeting a cloud OTLP endpoint that requires auth headers.

---

## Configuration Reference

### Minimal (Aspire / Local)

```json
{
  "runtime": {
    "telemetry": {
      "open-telemetry": {
        "enabled": true,
        "service-name": "@env('OTEL_SERVICE_NAME')",
        "endpoint": "@env('OTEL_EXPORTER_OTLP_ENDPOINT')",
        "exporter-protocol": "grpc"
      }
    }
  }
}
```

Aspire provides both env vars automatically. No other fields required.

### Full (Cloud / Authenticated Endpoint)

```json
{
  "runtime": {
    "telemetry": {
      "open-telemetry": {
        "enabled": true,
        "service-name": "@env('OTEL_SERVICE_NAME')",
        "endpoint": "@env('OTEL_EXPORTER_OTLP_ENDPOINT')",
        "exporter-protocol": "grpc",
        "headers": "@env('OTEL_EXPORTER_OTLP_HEADERS')"
      }
    }
  }
}
```

Only include `headers` when the env var is guaranteed to exist (e.g., set in `.env` or cloud config).

### Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `enabled` | boolean | Yes | Enable/disable OTEL export |
| `endpoint` | string | Yes | OTLP collector URL (e.g., `http://localhost:4317`) |
| `service-name` | string | Yes | Service name in traces (e.g., `dab`, `data-api`) |
| `exporter-protocol` | string | No | `grpc` (default) or `http/protobuf` |
| `headers` | string | No | Auth headers for OTLP endpoint — **omit if not needed** |

---

## CLI: `dab add-telemetry`

```bash
dab add-telemetry \
    -c dab-config.json \
    --otel-enabled true \
    --otel-endpoint "http://localhost:4317" \
    --otel-protocol "grpc" \
    --otel-service-name "dab"
```

| Flag | Purpose |
|------|---------|
| `--otel-enabled` | Enable OpenTelemetry |
| `--otel-endpoint` | OTLP collector endpoint |
| `--otel-protocol` | `grpc` or `http/protobuf` |
| `--otel-service-name` | Service name in traces |
| `--otel-headers` | Auth headers (only for cloud endpoints) |

> **Note:** `dab configure` does not support telemetry options — use `dab add-telemetry` only.

---

## What DAB Emits

### Traces (Activities)

DAB creates OpenTelemetry activities for:

- Incoming HTTP requests (REST endpoints)
- GraphQL operations
- MCP operations
- Database queries (per entity)
- Internal middleware steps (request handling, error tracking)

Each activity includes tags:

| Tag | Example |
|-----|---------|
| `http.method` | `GET`, `POST` |
| `http.url` | `/api/Product` |
| `status.code` | `200`, `500` |
| `action.type` | `Read`, `Create` |
| `user.role` | `anonymous` |
| `data-source.type` | `mssql` |
| `api.type` | `REST`, `GraphQL` |

Errors and exceptions are traced with full detail.

### Metrics

| Metric | Type | Labels |
|--------|------|--------|
| Total Requests | Counter | method, status, endpoint, api type |
| Errors | Counter | error type, method, status, endpoint |
| Request Duration | Histogram (ms) | method, status, endpoint, api type |
| Active Requests | UpDownCounter | — |

---

## Orchestration Patterns

### Aspire

Aspire auto-injects OTEL env vars. Use `.WithOtlpExporter()` on the DAB container:

```csharp
var dabServer = builder
    .AddContainer("data-api", "azure-databases/data-api-builder", "1.7.83-rc")
    .WithImageRegistry("mcr.microsoft.com")
    .WithOtlpExporter()          // enables OTEL export to Aspire collector
    .WithEnvironment("MSSQL_CONNECTION_STRING", sqlDatabase)
    .WaitFor(sqlDatabase);
```

The Aspire Dashboard at `http://localhost:15888` shows traces, metrics, and logs automatically.

**Do NOT add `headers` to `dab-config.json` when using Aspire locally.**

### Docker Compose

Add an OTEL collector (e.g., Jaeger) and pass env vars:

```yaml
services:
  api-server:
    image: mcr.microsoft.com/azure-databases/data-api-builder:1.7.83-rc
    environment:
      OTEL_SERVICE_NAME: data-api
      OTEL_EXPORTER_OTLP_ENDPOINT: http://jaeger:4317
    depends_on:
      sql-server:
        condition: service_healthy

  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"   # Jaeger UI
      - "4317:4317"     # OTLP gRPC
```

### Azure (Application Insights)

For Azure deployments, use Application Insights instead of (or alongside) OTEL:

```json
{
  "runtime": {
    "telemetry": {
      "application-insights": {
        "enabled": true,
        "connection-string": "@env('APPLICATIONINSIGHTS_CONNECTION_STRING')"
      }
    }
  }
}
```

Or combine both — DAB supports Application Insights and OTEL simultaneously.

---

## Troubleshooting

### DAB crash loop on startup

**Symptom:** Container restarts repeatedly with deserialization error.

**Cause:** An `@env()` reference in the telemetry config points to an unset environment variable.

**Fix:** Check that every `@env('VAR')` in the `open-telemetry` block has a corresponding env var set. Remove `headers` if `OTEL_EXPORTER_OTLP_HEADERS` is not defined.

### No traces appearing in Aspire Dashboard

1. Verify `.WithOtlpExporter()` is on the DAB container resource in `Program.cs`
2. Confirm `open-telemetry.enabled` is `true` in `dab-config.json`
3. Check that `endpoint` resolves — Aspire injects `OTEL_EXPORTER_OTLP_ENDPOINT` automatically
4. Ensure DAB container is healthy (`/health` returns 200)

### Traces appear but no metrics

The .NET OTEL SDK exports metrics on a periodic interval. Short-lived containers may exit before metrics flush. Allow a graceful shutdown window.

### `exporter-protocol` mismatch

If the collector expects HTTP and DAB sends gRPC (or vice versa), traces will silently drop. Match `exporter-protocol` to your collector's intake port:

| Protocol | Typical Port |
|----------|-------------|
| `grpc` | 4317 |
| `http/protobuf` | 4318 |

---

## Decision Tree

```
User wants telemetry in DAB
├── Using Aspire?
│   ├── Yes → Use minimal config (service-name + endpoint via @env)
│   │         Add .WithOtlpExporter() in Program.cs
│   │         Do NOT include headers field
│   │         Traces appear in Aspire Dashboard automatically
│   └── No
│       ├── Using Docker Compose?
│       │   ├── Add Jaeger or OTEL collector service
│       │   └── Set OTEL_SERVICE_NAME and OTEL_EXPORTER_OTLP_ENDPOINT env vars
│       └── Deploying to Azure?
│           ├── Use Application Insights (simpler)
│           └── Or use OTEL with authenticated endpoint + headers
```

---

## References

- [DAB OpenTelemetry docs](https://learn.microsoft.com/en-us/azure/data-api-builder/concept/monitor/open-telemetry?tabs=bash)
- [DAB Application Insights docs](https://learn.microsoft.com/en-us/azure/data-api-builder/concept/monitor/application-insights)
- [DAB runtime configuration](https://learn.microsoft.com/en-us/azure/data-api-builder/configuration/runtime)
- [.NET OpenTelemetry SDK](https://opentelemetry.io/docs/languages/dotnet/)
