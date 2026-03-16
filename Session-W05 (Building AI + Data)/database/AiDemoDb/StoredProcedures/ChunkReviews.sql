/*
    ChunkReviews — Text chunking demo
    Finds reviews with no chunks and breaks them into ~800-char pieces
    with overlap. Pure T-SQL — no external dependencies.
*/
CREATE OR ALTER PROCEDURE dbo.ChunkReviews
    @BatchSize INT = 10,
    @ChunkSize INT = 800,
    @Overlap   INT = 25
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ReviewVector (ReviewId, Chunk)
    SELECT r.ReviewId, c.chunk
    FROM (
        SELECT TOP (@BatchSize) r.ReviewId, r.ReviewText
        FROM dbo.Review r
        WHERE NOT EXISTS (SELECT 1 FROM dbo.ReviewVector rv WHERE rv.ReviewId = r.ReviewId)
        ORDER BY r.ReviewId
    ) r
    CROSS APPLY AI_GENERATE_CHUNKS(
        SOURCE     = r.ReviewText,
        CHUNK_TYPE = FIXED,
        CHUNK_SIZE = @ChunkSize,
        OVERLAP    = @Overlap
    ) c;

    SELECT COUNT(*) AS ChunksCreated FROM dbo.ReviewVector WHERE Embedding IS NULL AND Chunk IS NOT NULL;
END
GO
