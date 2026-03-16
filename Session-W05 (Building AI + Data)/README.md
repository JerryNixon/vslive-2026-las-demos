# Session W05 — Building AI + Data

Azure SQL AI capabilities demo: vector embeddings, text chunking, external REST endpoints, change tracking, and Azure Functions.

## Architecture

- **Azure SQL** (GP Serverless, centralus) — AiDemoDb with VECTOR(1536) support
- **Azure OpenAI** — text-embedding-3-large (1536 dimensions)
- **Azure Function** — SQL trigger binding on ReviewVector change tracking

## Prerequisites

- Azure CLI (`az`)
- .NET SDK 8+
- SqlPackage (`dotnet tool install -g microsoft.sqlpackage`)

## Deploy

```powershell
.\infra\azure-up.ps1
```

## Tear Down

```powershell
.\infra\azure-down.ps1
```

## Demo Flow

### 1. CREATE EXTERNAL MODEL

View `database/AiDemoDb/Scripts/CreateExternalModel.sql` — registers the Azure OpenAI deployment as a SQL-native model with credential and endpoint.

### 2. Chunk Reviews (manual T-SQL)

```sql
EXEC dbo.ChunkReviews @BatchSize = 10;
SELECT * FROM dbo.ReviewVector;
```

Breaks long review text into ~800-char chunks with 200-char overlap at sentence boundaries.

### 3. SP_INVOKE_EXTERNAL_REST_ENDPOINT

```sql
EXEC dbo.EmbedSingleReview @ReviewVectorId = 1;
```

Calls Azure OpenAI embeddings API directly from T-SQL, stores the result as VECTOR(1536).

### 4. Batch Embed

```sql
EXEC dbo.EmbedReviews @BatchSize = 10;
SELECT * FROM dbo.ReviewsPendingEmbedding;
```

### 5. Change Tracking + Azure Function

```sql
EXEC dbo.ToggleChangeTracking @Enable = 1;
INSERT INTO dbo.Review (ProductId, CustomerId, ReviewText)
VALUES (1, 1, 'Amazing model, the detail is incredible!');
```

The trigger clears the old embedding, change tracking detects the new row, and the Azure Function auto-embeds it.

## Database Objects

| Object | Type | Purpose |
|--------|------|---------|
| Category, Product, Customer, Review | Tables | Core domain |
| ReviewVector | Table | Chunks + VECTOR(1536) embeddings |
| ChunkReviews | Proc | T-SQL text chunking with overlap |
| EmbedSingleReview | Proc | REST call to Azure OpenAI |
| EmbedReviews | Proc | Batch wrapper for EmbedSingleReview |
| ToggleChangeTracking | Proc | Enable/disable CT on ReviewVector |
| ReviewChanged | Trigger | Clears embeddings on review change |
| ReviewsPendingEmbedding | View | Chunks without embeddings |
| text-embedding-3-large | External Model | Azure OpenAI registration |
