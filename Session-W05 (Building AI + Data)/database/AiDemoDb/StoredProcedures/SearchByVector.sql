CREATE OR ALTER PROCEDURE dbo.SearchByVector
    @SearchVector VECTOR(1536),
    @Top          INT   = 5,
    @Threshold    FLOAT = 0.6
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@Top)
        rv.Id,
        rv.ReviewId,
        r.ReviewText,
        rv.Chunk,
        VECTOR_DISTANCE('cosine', rv.Embedding, @SearchVector) AS distance
    FROM dbo.ReviewVector rv
    INNER JOIN dbo.Review r ON r.ReviewId = rv.ReviewId
    WHERE rv.Embedding IS NOT NULL
      AND VECTOR_DISTANCE('cosine', rv.Embedding, @SearchVector) < @Threshold
    ORDER BY distance;
END
GO
