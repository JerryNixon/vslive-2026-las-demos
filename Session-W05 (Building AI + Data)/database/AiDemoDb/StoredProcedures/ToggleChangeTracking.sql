/*
    ToggleChangeTracking — enable or disable change tracking on ReviewVector.
    Keeps it off while doing manual demos, flip it on for the Function demo.
    EXEC dbo.ToggleChangeTracking @Enable = 1;
*/
CREATE OR ALTER PROCEDURE dbo.ToggleChangeTracking
    @Enable BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @Enable = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.change_tracking_databases WHERE database_id = DB_ID())
            ALTER DATABASE CURRENT SET CHANGE_TRACKING = ON
                (CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);

        IF NOT EXISTS (
            SELECT 1 FROM sys.change_tracking_tables
            WHERE object_id = OBJECT_ID('dbo.ReviewVector')
        )
            ALTER TABLE dbo.ReviewVector ENABLE CHANGE_TRACKING;

        PRINT 'Change tracking ENABLED on dbo.ReviewVector';
    END
    ELSE
    BEGIN
        IF EXISTS (
            SELECT 1 FROM sys.change_tracking_tables
            WHERE object_id = OBJECT_ID('dbo.ReviewVector')
        )
            ALTER TABLE dbo.ReviewVector DISABLE CHANGE_TRACKING;

        IF EXISTS (SELECT 1 FROM sys.change_tracking_databases WHERE database_id = DB_ID())
            ALTER DATABASE CURRENT SET CHANGE_TRACKING = OFF;

        PRINT 'Change tracking DISABLED';
    END
END
GO
