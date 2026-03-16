-- ============================================================
-- Session H06: SQL + JSON Demo
-- ============================================================
-- DAB: https://ca-dab-api.wonderfulplant-f63acab2.westus2.azurecontainerapps.io
-- SQL: sql-h06-wovkqx7yuk3by.database.windows.net
-- Admin: sqladmin / Sql@dmin2026!
-- DAB user: crmUser / P@ssw0rd!
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- PART A: THE CRM DATABASE
-- ════════════════════════════════════════════════════════════

USE CrmDb;
GO

-- 1. Contacts and addresses in CRM
SELECT * FROM dbo.Contact;
SELECT * FROM dbo.[Address];

-- 2. SSN visible to admin
SELECT ContactId, FirstName, LastName, SSN FROM dbo.Contact;

-- 3. SSN masked for crmUser (run as crmUser to see XXX-XX-####)
EXECUTE AS USER = 'crmUser';
SELECT ContactId, FirstName, LastName, SSN FROM dbo.Contact;
REVERT;

-- 4. crmUser cannot update SSN
EXECUTE AS USER = 'crmUser';
BEGIN TRY
    UPDATE dbo.Contact SET SSN = '999-99-9999' WHERE ContactId = 1;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS BlockedMessage;
END CATCH
REVERT;

-- 5. crmUser CAN update other columns
EXECUTE AS USER = 'crmUser';
UPDATE dbo.Contact SET Phone = '555-9999' WHERE ContactId = 1;
SELECT ContactId, FirstName, Phone, SSN FROM dbo.Contact WHERE ContactId = 1;
UPDATE dbo.Contact SET Phone = '555-0001' WHERE ContactId = 1;
REVERT;


-- ════════════════════════════════════════════════════════════
-- PART B: IMPORT FROM CRM → COMPANY DB
-- ════════════════════════════════════════════════════════════

USE CompanyDb;
GO

-- 6. CompanyDb is empty before import
SELECT COUNT(*) AS Contacts FROM dbo.Contact;
SELECT COUNT(*) AS Addresses FROM dbo.[Address];

-- 7. Fetch from CRM via GraphQL (first 3)
EXEC dbo.Crm_01_Fetch
    @DabEndpointUrl = 'https://ca-dab-api.wonderfulplant-f63acab2.westus2.azurecontainerapps.io',
    @First = 3;

-- 8. Raw JSON in staging table
SELECT LEFT(RawJson, 500) AS JsonPreview FROM dbo.CrmRawJson;

-- 9. Parse contacts with OPENJSON
EXEC dbo.Crm_02_ParseContacts;

-- 10. Parse nested addresses with CROSS APPLY OPENJSON
EXEC dbo.Crm_03_ParseAddresses;

-- 11. MERGE import into tables
EXEC dbo.Crm_04_Import;

-- 12. Imported data with SSN (masked values from DAB)
SELECT ContactId, FirstName, LastName, SSN, ImportedOn FROM dbo.Contact;

-- 13. Full import (all 50 contacts)
EXEC dbo.Crm_01_Fetch
    @DabEndpointUrl = 'https://ca-dab-api.wonderfulplant-f63acab2.westus2.azurecontainerapps.io';
EXEC dbo.Crm_04_Import;
SELECT COUNT(*) AS Contacts FROM dbo.Contact;

-- 14. View: contacts joined with addresses
SELECT * FROM dbo.ContactsWithAddresses WHERE ContactId <= 3;


-- ════════════════════════════════════════════════════════════
-- PART C: WRITE BACK TO CRM
-- ════════════════════════════════════════════════════════════

-- 15. Modify a contact in CompanyDb
UPDATE dbo.Contact SET Email = 'admiral.kirk@starfleet.org' WHERE ContactId = 1;

-- 16. Build JSON payload (FOR JSON PATH)
EXEC dbo.Crm_05_BuildJson @ContactId = 1;

-- 17. Push back to CRM via REST PATCH
EXEC dbo.Crm_06_PushToCrm
    @DabEndpointUrl = 'https://ca-dab-api.wonderfulplant-f63acab2.westus2.azurecontainerapps.io',
    @ContactId = 1;

-- 18. Verify: CRM has the updated email
USE CrmDb;
GO
SELECT ContactId, FirstName, Email FROM dbo.Contact WHERE ContactId = 1;

-- 19. SSN was never touched (still original value)
SELECT ContactId, FirstName, SSN FROM dbo.Contact WHERE ContactId = 1;


-- ════════════════════════════════════════════════════════════
-- PART D: SQL SERVER AS A DOCUMENT DATABASE
-- ════════════════════════════════════════════════════════════

USE CompanyDb;
GO

-- 20. DocumentStore table with JSON data type
SELECT * FROM dbo.DocumentStore;

-- 21. Computed column from JSON property
SELECT Id, DocumentType, DisplayName FROM dbo.DocumentStore;

-- 22. Query inside JSON
SELECT Id, DisplayName,
       JSON_VALUE(Data, '$.department') AS Department,
       JSON_VALUE(Data, '$.status')     AS Status
FROM dbo.DocumentStore
WHERE JSON_VALUE(Data, '$.status') = 'active';

-- 23. Insert valid document
INSERT INTO dbo.DocumentStore (DocumentType, Data)
VALUES ('employee', '{"name": "Geordi LaForge", "email": "glaforge@starfleet.org", "department": "Engineering"}');
SELECT * FROM dbo.DocumentStore WHERE DisplayName = 'Geordi LaForge';

-- 24. Constraint: $.name is required
BEGIN TRY
    INSERT INTO dbo.DocumentStore (DocumentType, Data)
    VALUES ('test', '{"email": "nobody@test.com"}');
END TRY
BEGIN CATCH
    SELECT 'Blocked: name is required' AS ConstraintResult, ERROR_MESSAGE() AS Detail;
END CATCH

-- 25. Constraint: $.email must be valid format
BEGIN TRY
    INSERT INTO dbo.DocumentStore (DocumentType, Data)
    VALUES ('test', '{"name": "Bad Email", "email": "not-an-email"}');
END TRY
BEGIN CATCH
    SELECT 'Blocked: invalid email' AS ConstraintResult, ERROR_MESSAGE() AS Detail;
END CATCH

-- 26. Index seek on computed column
SELECT DisplayName FROM dbo.DocumentStore WHERE DisplayName = 'Spock Grayson';

-- 27. Cleanup demo insert
DELETE FROM dbo.DocumentStore WHERE DisplayName = 'Geordi LaForge';
