CREATE OR ALTER PROCEDURE dbo.EmbedSingleReview
    @ReviewVectorId INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.ReviewVector
    SET Embedding = AI_GENERATE_EMBEDDINGS(Chunk USE MODEL [text-embedding-3-large])
    WHERE Id = @ReviewVectorId
      AND Chunk IS NOT NULL
      AND Embedding IS NULL;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR(N'Row %d not found, has no chunk, or is already embedded.', 16, 1, @ReviewVectorId);
        RETURN;
    END

    SELECT @ReviewVectorId AS Id, 'Embedded' AS Status;
END
GO
