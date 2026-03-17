-- ═══════════════════════════════════════════════════════════
-- Session H06: SQL + JSON
-- ═══════════════════════════════════════════════════════════
-- SQL: sql-h06-wovkqx7yuk3by.database.windows.net
-- DAB: https://ca-dab-api.wonderfulplant-f63acab2.westus2.azurecontainerapps.io
-- CrmDb: contacts + addresses (source)
-- CompanyDb: imported data + document store
-- Admin: sqladmin / Sql@dmin2026!
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- 0. The CRM database — contacts and addresses
-- ═══════════════════════════════════════════════════════════

EXEC ResetDemo;
GO

SELECT * FROM dbo.Contact;
SELECT * FROM dbo.[Address];

-- ═══════════════════════════════════════════════════════════
-- 1. Dynamic Data Masking — SSN column
-- ═══════════════════════════════════════════════════════════

/*  MASKED WITH (FUNCTION = ...) — hide sensitive data per user

    CREATE TABLE dbo.Contact (
        SSN CHAR(11) MASKED WITH (FUNCTION = 'partial(0,"XXX-XX-",4)')
    );

    Admin sees full SSN; crmUser sees XXX-XX-####
*/

-- Admin sees full value
SELECT ContactId, FirstName, LastName, SSN FROM dbo.Contact;

-- crmUser sees masked value
EXECUTE AS USER = 'crmUser';
SELECT ContactId, FirstName, LastName, SSN FROM dbo.Contact;
REVERT;

-- ═══════════════════════════════════════════════════════════
-- 2. Column-level security — crmUser cannot update SSN
-- ═══════════════════════════════════════════════════════════

/*  DENY UPDATE ON dbo.Contact (SSN) TO crmUser;
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Contact TO crmUser;

    crmUser can update any column except SSN.
*/

EXECUTE AS USER = 'crmUser';
BEGIN TRY
    UPDATE dbo.Contact SET SSN = '999-99-9999' WHERE ContactId = 1;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS BlockedMessage;
END CATCH
REVERT;

-- crmUser CAN update other columns
EXECUTE AS USER = 'crmUser';
UPDATE dbo.Contact SET Phone = '555-9999' WHERE ContactId = 1;
SELECT ContactId, FirstName, Phone, SSN FROM dbo.Contact WHERE ContactId = 1;
UPDATE dbo.Contact SET Phone = '555-0001' WHERE ContactId = 1;
REVERT;

-- ═══════════════════════════════════════════════════════════
-- 3. Import from CRM — fetch via DAB GraphQL
-- ═══════════════════════════════════════════════════════════

/*  sp_invoke_external_rest_endpoint — call REST/GraphQL from T-SQL

    EXEC sp_invoke_external_rest_endpoint
        @url      = 'https://.../graphql',
        @method   = 'POST',
        @payload  = '{"query": "{ contacts { items { ... } } }"}',
        @response = @response OUTPUT;
*/

USE CompanyDb;
EXEC ResetDemo;
GO

-- CompanyDb is empty before import
SELECT COUNT(*) AS Contacts FROM dbo.Contact;
SELECT COUNT(*) AS Addresses FROM dbo.[Address];

-- GraphQL at https://ca-dab-api.agreeablesky-bf194cf3.westus2.azurecontainerapps.io/graphql
-- GraphQL at https://ca-dab-api.agreeablesky-bf194cf3.westus2.azurecontainerapps.io/graphql?query=%7B%20contacts%20%7B%20items%20%7B%20ContactId%20FirstName%20LastName%20SSN%20addresses%20%7B%20items%20%7B%20Street%20City%20State%20ZipCode%20%7D%20%7D%20%7D%20%7D%7D

-- Fetch first 3 contacts from CRM via GraphQL
DECLARE @url NVARCHAR(500) = 'https://ca-dab-api.agreeablesky-bf194cf3.westus2.azurecontainerapps.io';
EXEC dbo.Crm_Fetch
    @DabEndpointUrl = @url,
    @First = 3;

-- ═══════════════════════════════════════════════════════════
-- 4. Parse JSON — OPENJSON shreds contacts
-- ═══════════════════════════════════════════════════════════

/*  OPENJSON — shred a JSON array into relational rows
*/

-- Raw JSON in staging table
DECLARE @json NVARCHAR(MAX) 
    = (SELECT RawJson FROM dbo.CrmRawJson);

SELECT @json;

SELECT JSON_QUERY(@json, '$.data.contacts.items[0]') AS FirstContact FROM dbo.CrmRawJson;

SELECT JSON_VALUE(@json, '$.data.contacts.items[0].FirstName') AS FirstName;

SELECT ContactId, FirstName, LastName
    FROM OPENJSON(@json, '$.data.contacts.items')
    WITH (
        ContactId INT '$.ContactId',
        FirstName NVARCHAR(100) '$.FirstName',
        LastName  NVARCHAR(100) '$.LastName'
    );

SELECT c.ContactId, a.Street, a.City
FROM OPENJSON(@json, '$.data.contacts.items') WITH (
    ContactId INT '$.ContactId',
    addresses NVARCHAR(MAX) '$.addresses' AS JSON
) c
CROSS APPLY OPENJSON(c.addresses, '$.items') WITH (
    Street NVARCHAR(200) '$.Street',
    City   NVARCHAR(100) '$.City'
) a;

-- Parse contacts
EXEC dbo.Crm_ParseContacts;
EXEC dbo.Crm_ParseAddresses;

-- ═══════════════════════════════════════════════════════════
-- 6. MERGE import into CompanyDb tables
-- ═══════════════════════════════════════════════════════════

/*  MERGE — idempotent upsert (insert or update)
*/

EXEC dbo.Crm_Import;

-- Imported data (SSN is masked value from DAB)
SELECT ContactId, FirstName, LastName, SSN, ImportedOn FROM dbo.Contact;

-- ═══════════════════════════════════════════════════════════
-- 7. Full import — all 50 contacts
-- ═══════════════════════════════════════════════════════════

DECLARE @url NVARCHAR(500) = 'https://ca-dab-api.agreeablesky-bf194cf3.westus2.azurecontainerapps.io';
EXEC dbo.Crm_Fetch
    @DabEndpointUrl = @url;
EXEC dbo.Crm_Import;
SELECT COUNT(*) AS Contacts FROM dbo.Contact;

-- View: contacts joined with addresses
SELECT * FROM dbo.ContactsWithAddresses WHERE ContactId <= 3;

-- ═══════════════════════════════════════════════════════════
-- 8. Write back to CRM — FOR JSON PATH builds the payload
-- ═══════════════════════════════════════════════════════════

/*  FOR JSON PATH — build JSON from relational data

    SELECT TOP 1 FirstName, LastName, Email, Phone
    FROM dbo.Contact
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
*/

-- Modify a contact in CompanyDb
UPDATE dbo.Contact SET Email = 'admiral.kirk@starfleet.org' WHERE ContactId = 1;

-- Build JSON payload
EXEC dbo.Crm_BuildJson @ContactId = 1;

-- ═══════════════════════════════════════════════════════════
-- 9. Push back to CRM via REST PATCH
-- ═══════════════════════════════════════════════════════════

/*  sp_invoke_external_rest_endpoint + FOR JSON PATH
    relational → JSON → REST PATCH → CRM updated
*/

DECLARE @url NVARCHAR(500) = 'https://ca-dab-api.agreeablesky-bf194cf3.westus2.azurecontainerapps.io';
EXEC dbo.Crm_PushToCrm
    @DabEndpointUrl = @url,
    @ContactId = 1;

-- Verify: CRM has the updated email
USE CrmDb;
GO
SELECT ContactId, FirstName, Email FROM dbo.Contact WHERE ContactId = 1;

-- SSN was never touched (still original value)
SELECT ContactId, FirstName, SSN FROM dbo.Contact WHERE ContactId = 1;

-- ═══════════════════════════════════════════════════════════
-- 10. SQL Server as a document database — JSON data type
-- ═══════════════════════════════════════════════════════════

/*  JSON data type (SQL Server 2025) — native JSON column

    CREATE TABLE dbo.DocumentStore (
        Data JSON NOT NULL,
        DisplayName AS CAST(JSON_VALUE(Data, '$.name') AS NVARCHAR(200)),
        CONSTRAINT CK_NameRequired CHECK (JSON_VALUE(Data, '$.name') IS NOT NULL)
    );
*/

USE CompanyDb;
GO

SELECT * FROM dbo.DocumentStore;

-- Computed column from JSON property
SELECT Id, DocumentType, DisplayName FROM dbo.DocumentStore;

-- ═══════════════════════════════════════════════════════════
-- 11. Query inside JSON — JSON_VALUE extracts scalar values
-- ═══════════════════════════════════════════════════════════

/*  JSON_VALUE(column, '$.path') — extract a scalar from JSON

    SELECT JSON_VALUE(Data, '$.department') AS Department
    FROM dbo.DocumentStore
    WHERE JSON_VALUE(Data, '$.status') = 'active';
*/

SELECT Id, DisplayName,
       JSON_VALUE(Data, '$.department') AS Department,
       JSON_VALUE(Data, '$.status')     AS Status
FROM dbo.DocumentStore
WHERE JSON_VALUE(Data, '$.status') = 'active';

-- ═══════════════════════════════════════════════════════════
-- 12. JSON constraints — schema enforcement on schemaless data
-- ═══════════════════════════════════════════════════════════

-- Insert valid document
INSERT INTO dbo.DocumentStore (DocumentType, Data)
VALUES ('employee', '{"name": "Geordi LaForge", "email": "glaforge@starfleet.org", "department": "Engineering"}');
SELECT * FROM dbo.DocumentStore WHERE DisplayName = 'Geordi LaForge';

-- Constraint: $.name is required
BEGIN TRY
    INSERT INTO dbo.DocumentStore (DocumentType, Data)
    VALUES ('test', '{"email": "nobody@test.com"}');
END TRY
BEGIN CATCH
    SELECT 'Blocked: name is required' AS ConstraintResult, ERROR_MESSAGE() AS Detail;
END CATCH

-- Constraint: $.email must be valid format
BEGIN TRY
    INSERT INTO dbo.DocumentStore (DocumentType, Data)
    VALUES ('test', '{"name": "Bad Email", "email": "not-an-email"}');
END TRY
BEGIN CATCH
    SELECT 'Blocked: invalid email' AS ConstraintResult, ERROR_MESSAGE() AS Detail;
END CATCH

-- ═══════════════════════════════════════════════════════════
-- 13. Index on computed column — JSON property → index seek
-- ═══════════════════════════════════════════════════════════

/*  Computed column + index = fast JSON property lookups

    DisplayName AS CAST(JSON_VALUE(Data, '$.name') AS NVARCHAR(200))
    CREATE INDEX IX_DocumentStore_DisplayName ON dbo.DocumentStore (DisplayName);
*/

SELECT DisplayName FROM dbo.DocumentStore WHERE DisplayName = 'Spock Grayson';

-- Cleanup demo insert
DELETE FROM dbo.DocumentStore WHERE DisplayName = 'Geordi LaForge';
