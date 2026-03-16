CREATE OR ALTER PROCEDURE dbo.ToggleVectorIndex
    @Enable BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @Enable = 1
    BEGIN
        ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;

        IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ReviewVector_Embedding' AND object_id = OBJECT_ID('dbo.ReviewVector'))
            CREATE VECTOR INDEX IX_ReviewVector_Embedding
            ON dbo.ReviewVector(Embedding)
            WITH (METRIC = 'cosine', TYPE = 'diskann');

        PRINT 'Vector index CREATED — search is fast, DML is blocked.';
    END
    ELSE
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ReviewVector_Embedding' AND object_id = OBJECT_ID('dbo.ReviewVector'))
            DROP INDEX IX_ReviewVector_Embedding ON dbo.ReviewVector;

        PRINT 'Vector index DROPPED — DML is allowed, search uses exact scan.';
    END
END
GO
