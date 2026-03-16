CREATE OR ALTER PROCEDURE dbo.ResetDemo
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ReviewVector_Embedding' AND object_id = OBJECT_ID('dbo.ReviewVector'))
        DROP INDEX IX_ReviewVector_Embedding ON dbo.ReviewVector;

    IF EXISTS (SELECT 1 FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID('dbo.ReviewVector'))
        ALTER TABLE dbo.ReviewVector DISABLE CHANGE_TRACKING;

    IF EXISTS (SELECT 1 FROM sys.change_tracking_databases WHERE database_id = DB_ID())
        ALTER DATABASE CURRENT SET CHANGE_TRACKING = OFF;

    DELETE FROM dbo.ReviewVector;

    DISABLE TRIGGER dbo.ReviewChanged ON dbo.Review;

    MERGE dbo.Review AS t
    USING dbo.ReviewSeed AS s ON t.ReviewId = s.ReviewId
    WHEN MATCHED AND t.ReviewText <> s.ReviewText
        THEN UPDATE SET ReviewText = s.ReviewText;

    ENABLE TRIGGER dbo.ReviewChanged ON dbo.Review;

    PRINT 'Demo reset to initial state.';
END
GO
