-- Chunks that still need an embedding vector
CREATE OR ALTER VIEW dbo.ReviewsPendingEmbedding
AS
SELECT rv.Id, rv.ReviewId, rv.Chunk
FROM dbo.ReviewVector rv
WHERE rv.Embedding IS NULL
  AND rv.Chunk IS NOT NULL;
GO
