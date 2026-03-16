/*
    Crm_04_Import
    ─────────────
    Reads raw JSON from dbo.CrmRawJson (populated by Crm_01_Fetch)
    and MERGE-imports contacts + addresses into CompanyDb tables.

    Uses MERGE so you can run it multiple times without duplicates.

    EXEC dbo.Crm_04_Import;
*/
CREATE OR ALTER PROCEDURE dbo.Crm_04_Import
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @json NVARCHAR(MAX) = (SELECT RawJson FROM dbo.CrmRawJson);

    IF @json IS NULL
    BEGIN
        THROW 50004, N'No data in CrmRawJson. Run Crm_01_Fetch first.', 1;
    END

    -- Parse contacts
    SELECT
        ContactId, FirstName, LastName, Email, Phone, SSN,
        JSON_QUERY(addresses, '$.items') AS AddressesJson
    INTO #Contacts
    FROM OPENJSON(@json, '$.data.contacts.items') WITH (
        ContactId   INT             '$.ContactId',
        FirstName   NVARCHAR(100)   '$.FirstName',
        LastName    NVARCHAR(100)   '$.LastName',
        Email       NVARCHAR(200)   '$.Email',
        Phone       NVARCHAR(20)    '$.Phone',
        SSN         CHAR(11)        '$.SSN',
        addresses   NVARCHAR(MAX)   '$.addresses' AS JSON
    );

    -- Parse addresses
    SELECT
        c.ContactId, a.AddressId, a.Street, a.City, a.[State], a.ZipCode
    INTO #Addresses
    FROM #Contacts c
    CROSS APPLY OPENJSON(c.AddressesJson) WITH (
        AddressId   INT             '$.AddressId',
        Street      NVARCHAR(200)   '$.Street',
        City        NVARCHAR(100)   '$.City',
        [State]     NVARCHAR(50)    '$.State',
        ZipCode     NVARCHAR(10)    '$.ZipCode'
    ) a;

    -- MERGE into CompanyDb tables (idempotent)
    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE dbo.Contact AS tgt
        USING #Contacts AS src ON tgt.ContactId = src.ContactId
        WHEN MATCHED THEN UPDATE SET
            FirstName = src.FirstName, LastName = src.LastName,
            Email = src.Email, Phone = src.Phone, SSN = src.SSN
        WHEN NOT MATCHED THEN INSERT (ContactId, FirstName, LastName, Email, Phone, SSN)
            VALUES (src.ContactId, src.FirstName, src.LastName, src.Email, src.Phone, src.SSN);

        MERGE dbo.[Address] AS tgt
        USING #Addresses AS src ON tgt.AddressId = src.AddressId
        WHEN MATCHED THEN UPDATE SET
            ContactId = src.ContactId, Street = src.Street,
            City = src.City, [State] = src.[State], ZipCode = src.ZipCode
        WHEN NOT MATCHED THEN INSERT (AddressId, ContactId, Street, City, [State], ZipCode)
            VALUES (src.AddressId, src.ContactId, src.Street, src.City, src.[State], src.ZipCode);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    -- Show final state
    SELECT
        c.ContactId, c.FirstName, c.LastName, c.ImportedOn,
        a.Street, a.City, a.[State]
    FROM dbo.Contact c
    LEFT JOIN dbo.[Address] a ON c.ContactId = a.ContactId
    ORDER BY c.ContactId, a.AddressId;

    DROP TABLE #Contacts;
    DROP TABLE #Addresses;
END
GO
