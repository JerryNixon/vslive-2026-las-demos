-- When a review is inserted or updated, clear its vector chunks so they get regenerated
CREATE OR ALTER TRIGGER dbo.ReviewChanged
ON dbo.Review
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DELETE rv
    FROM dbo.ReviewVector rv
    INNER JOIN inserted i ON rv.ReviewId = i.ReviewId;
END
GO
