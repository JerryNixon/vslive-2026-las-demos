/*
    Crm_ParseAddresses
    ──────────────────
    Reads raw JSON from dbo.CrmRawJson (populated by Crm_Fetch)
    and shreds the nested addresses using OPENJSON + CROSS APPLY.

    This is the key demo step: showing how CROSS APPLY handles
    the one-to-many nesting (each contact has N addresses).

    EXEC dbo.Crm_ParseAddresses;
*/
CREATE OR ALTER PROCEDURE dbo.Crm_ParseAddresses
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @json NVARCHAR(MAX) = (SELECT RawJson FROM dbo.CrmRawJson);

    IF @json IS NULL
    BEGIN
        THROW 50003, N'No data in CrmRawJson. Run Crm_Fetch first.', 1;
    END

    SELECT
        c.ContactId,
        c.FirstName + N' ' + c.LastName AS ContactName,
        a.AddressId,
        a.Street,
        a.City,
        a.[State],
        a.ZipCode
    FROM OPENJSON(@json, '$.data.contacts.items') WITH (
        ContactId   INT             '$.ContactId',
        FirstName   NVARCHAR(100)   '$.FirstName',
        LastName    NVARCHAR(100)   '$.LastName',
        addresses   NVARCHAR(MAX)   '$.addresses' AS JSON
    ) c
    CROSS APPLY OPENJSON(c.addresses, '$.items') WITH (
        AddressId   INT             '$.AddressId',
        Street      NVARCHAR(200)   '$.Street',
        City        NVARCHAR(100)   '$.City',
        [State]     NVARCHAR(50)    '$.State',
        ZipCode     NVARCHAR(10)    '$.ZipCode'
    ) a;
END
GO
