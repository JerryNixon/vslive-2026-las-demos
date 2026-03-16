/*
    ResetDemo
    ─────────
    Resets CompanyDb to its pre-demo state.
    - Clears imported contacts and addresses
    - Clears CRM staging table
    - Resets DocumentStore to seed data only

    EXEC dbo.ResetDemo;
*/
CREATE OR ALTER PROCEDURE dbo.ResetDemo
AS
BEGIN
    SET NOCOUNT ON;

    -- Clear imported data (address FK first)
    DELETE FROM dbo.[Address];
    DELETE FROM dbo.Contact;

    -- Clear staging table
    TRUNCATE TABLE dbo.CrmRawJson;

    -- Reset DocumentStore to seed data only (remove demo inserts)
    DELETE FROM dbo.DocumentStore WHERE DisplayName = 'Geordi LaForge';

    PRINT 'CompanyDb reset to initial state.';
END
GO
