CREATE OR ALTER PROCEDURE dbo.SearchByText
    @SearchText NVARCHAR(MAX),
    @Top        INT   = 5,
    @Threshold  FLOAT = 0.6
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @p JSON = N'{"dimensions":1536}';

    DECLARE @vector VECTOR(1536) = AI_GENERATE_EMBEDDINGS(@SearchText USE MODEL [text-embedding-3-large] PARAMETERS @p);

    EXEC dbo.SearchByVector @SearchVector = @vector, @Top = @Top, @Threshold = @Threshold;
END
GO
