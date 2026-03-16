CREATE OR ALTER PROCEDURE dbo.EmbedReviews
    @BatchSize INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE TOP (@BatchSize) rv
    SET Embedding = AI_GENERATE_EMBEDDINGS(rv.Chunk USE MODEL [text-embedding-3-large])
    FROM dbo.ReviewVector rv
    WHERE rv.Chunk IS NOT NULL
      AND rv.Embedding IS NULL;

    SELECT @@ROWCOUNT AS EmbeddingsGenerated;
END
GO
