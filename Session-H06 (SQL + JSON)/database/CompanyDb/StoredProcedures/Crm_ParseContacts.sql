/*
    Crm_ParseContacts
    ─────────────────
    Reads raw JSON from dbo.CrmRawJson (populated by Crm_Fetch)
    and shreds it into contact rows using OPENJSON.

    EXEC dbo.Crm_ParseContacts;
*/
CREATE OR ALTER PROCEDURE dbo.Crm_ParseContacts
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @json NVARCHAR(MAX) = (SELECT RawJson FROM dbo.CrmRawJson);

    IF @json IS NULL
    BEGIN
        THROW 50002, N'No data in CrmRawJson. Run Crm_Fetch first.', 1;
    END

    SELECT
        ContactId,
        FirstName,
        LastName,
        Email,
        Phone,
        SSN
    FROM OPENJSON(@json, '$.data.contacts.items') WITH (
        ContactId   INT             '$.ContactId',
        FirstName   NVARCHAR(100)   '$.FirstName',
        LastName    NVARCHAR(100)   '$.LastName',
        Email       NVARCHAR(200)   '$.Email',
        Phone       NVARCHAR(20)    '$.Phone',
        SSN         CHAR(11)        '$.SSN'
    );
END
GO
