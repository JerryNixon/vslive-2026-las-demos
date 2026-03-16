/*
    Crm_05_BuildJson
    ────────────────
    Builds the JSON payload for a single contact from the CompanyDb
    relational tables, exactly as DAB REST expects it for a PATCH.

    Shows: relational data → JSON using FOR JSON PATH.

    EXEC dbo.Crm_05_BuildJson @ContactId = 1;
*/
CREATE OR ALTER PROCEDURE dbo.Crm_05_BuildJson
    @ContactId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Contact WHERE ContactId = @ContactId)
    BEGIN
        DECLARE @msg NVARCHAR(200) = N'ContactId ' + CAST(@ContactId AS NVARCHAR(10)) + N' not found in CompanyDb.';
        THROW 50005, @msg, 1;
    END

    -- Build the REST PATCH payload (only updatable columns, no PK)
    DECLARE @json NVARCHAR(MAX);

    SELECT @json = (
        SELECT
            c.FirstName,
            c.LastName,
            c.Email,
            c.Phone
        FROM dbo.Contact c
        WHERE c.ContactId = @ContactId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    -- Show the contact and the JSON side-by-side
    SELECT
        c.ContactId,
        c.FirstName,
        c.LastName,
        c.Email,
        c.Phone,
        @json AS RestPayload
    FROM dbo.Contact c
    WHERE c.ContactId = @ContactId;
END
GO
