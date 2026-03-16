-- When a review is inserted or updated, clear its vector chunks and re-chunk
CREATE OR ALTER TRIGGER dbo.ReviewChanged
ON dbo.Review
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Remove stale chunks
    DELETE rv
    FROM dbo.ReviewVector rv
    INNER JOIN inserted i ON rv.ReviewId = i.ReviewId;

    -- Re-chunk each affected review
    DECLARE @rid INT;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT ReviewId FROM inserted;
    OPEN cur;
    FETCH NEXT FROM cur INTO @rid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.ChunkReviews @ReviewId = @rid;
        FETCH NEXT FROM cur INTO @rid;
    END
    CLOSE cur;
    DEALLOCATE cur;
END
GO
