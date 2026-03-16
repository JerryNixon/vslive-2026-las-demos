-- ═══════════════════════════════════════════════════════════
-- Session W05: Building AI + Data
-- ═══════════════════════════════════════════════════════════
-- SQL: sql-w05-e4gm3vxte255g.database.windows.net
-- Database: AiDemoDb
-- Admin: sqladmin / (see .env)
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- 0. Reset (makes the demo idempotent — safe to re-run)
-- ═══════════════════════════════════════════════════════════

EXEC dbo.ResetDemo;

-- ═══════════════════════════════════════════════════════════
-- 1. Explore the seed data
-- ═══════════════════════════════════════════════════════════

SELECT * FROM dbo.Category;
SELECT * FROM dbo.Product;
SELECT * FROM dbo.Customer;
SELECT * FROM dbo.Review;
SELECT * FROM dbo.ReviewVector;

/*  CREATE EXTERNAL MODEL — register an Azure OpenAI deployment

    CREATE EXTERNAL MODEL [text-embedding-3-large]
    WITH (
        LOCATION   = 'https://<endpoint>/openai/deployments/<name>',
        API_FORMAT = 'OpenAI',
        MODEL      = 'text-embedding-3-large',
        CREDENTIAL = [OpenAIEmbedding],
        MODEL_TYPE = EMBEDDINGS
    );
*/
SELECT * FROM sys.external_models;

-- ═══════════════════════════════════════════════════════════
-- 2. Chunk reviews into smaller pieces
-- ═══════════════════════════════════════════════════════════

/*  AI_GENERATE_CHUNKS — native T-SQL chunking function

    SELECT c.chunk, c.chunk_order, c.chunk_length
    FROM dbo.Review AS r
    CROSS APPLY AI_GENERATE_CHUNKS(
        SOURCE     = r.ReviewText,
        CHUNK_TYPE = FIXED,
        CHUNK_SIZE = 800,
        OVERLAP    = 25
    ) AS c;
*/

DELETE FROM dbo.ReviewVector;
DBCC CHECKIDENT ('dbo.ReviewVector', RESEED, 0);
SELECT * FROM dbo.ReviewVector;
 
EXEC dbo.ChunkReviews @BatchSize = 5;
SELECT * FROM dbo.ReviewVector;

-- ═══════════════════════════════════════════════════════════
-- 3. Embed a single chunk via Azure OpenAI REST call
-- ═══════════════════════════════════════════════════════════

/*  AI_GENERATE_EMBEDDINGS — native T-SQL embedding function

    UPDATE rv
    SET Embedding = AI_GENERATE_EMBEDDINGS(rv.Chunk USE MODEL [text-embedding-3-large])
    FROM dbo.ReviewVector rv
    WHERE rv.Embedding IS NULL;
*/

EXEC dbo.EmbedSingleReview @ReviewVectorId = 1;
SELECT * FROM dbo.ReviewVector

-- ═══════════════════════════════════════════════════════════
-- 4. Batch embed all pending chunks
-- ═══════════════════════════════════════════════════════════

SELECT * FROM dbo.ReviewVector
EXEC dbo.EmbedReviews @BatchSize = 50;
SELECT * FROM dbo.ReviewVector

-- ═══════════════════════════════════════════════════════════
-- 5. Semantic search by text
-- ═══════════════════════════════════════════════════════════

/*  VECTOR_SEARCH — native nearest-neighbor search in T-SQL

    SELECT t.*, s.distance
    FROM VECTOR_SEARCH(
        TABLE      = dbo.ReviewVector AS t,
        COLUMN     = Embedding,
        SIMILAR_TO = @SearchVector,
        METRIC     = 'cosine',
        TOP_N      = 5
    ) AS s
    ORDER BY s.distance;
*/

EXEC dbo.SearchByText @SearchText = N'detailed craftsmanship and quality';
EXEC dbo.SearchByText @SearchText = N'childhood nostalgia';
EXEC dbo.SearchByText @SearchText = N'disappointing purchase';

-- ═══════════════════════════════════════════════════════════
-- 6. Enable DiskANN vector index for fast search
-- ═══════════════════════════════════════════════════════════

EXEC dbo.ToggleVectorIndex @Enable = 1;

EXEC dbo.SearchByText @SearchText = N'detailed craftsmanship and quality';

EXEC dbo.ToggleVectorIndex @Enable = 0;

-- ═══════════════════════════════════════════════════════════
-- 7. Trigger: update a review, embeddings invalidated
-- ═══════════════════════════════════════════════════════════

SELECT COUNT(*) AS BeforeUpdate FROM dbo.ReviewVector WHERE ReviewId = 1;

UPDATE dbo.Review SET ReviewText = N'Updated review text for testing trigger.' WHERE ReviewId = 1;

SELECT COUNT(*) AS AfterUpdate FROM dbo.ReviewVector WHERE ReviewId = 1;

-- ═══════════════════════════════════════════════════════════
-- 8. Re-chunk and re-embed after trigger
-- ═══════════════════════════════════════════════════════════

EXEC dbo.ChunkReviews @BatchSize = 5;
EXEC dbo.EmbedReviews @BatchSize = 5;

SELECT Id, ReviewId, LEFT(Chunk, 80) AS ChunkPreview, Embedding
FROM dbo.ReviewVector
WHERE ReviewId = 1;

-- ═══════════════════════════════════════════════════════════
-- 9. Enable change tracking for Azure Function pipeline
-- ═══════════════════════════════════════════════════════════

EXEC dbo.ToggleChangeTracking @Enable = 1;

-- ═══════════════════════════════════════════════════════════
-- 10. Cleanup: disable change tracking
-- ═══════════════════════════════════════════════════════════

EXEC dbo.ToggleChangeTracking @Enable = 0;
