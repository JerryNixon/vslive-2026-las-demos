/*
    Crm_ImportAll
    ------------
    Imports contacts and addresses from the CRM database via DAB's GraphQL endpoint.
    
    Flow:  CRM DB  →  DAB (GraphQL)  →  this stored proc  →  Company DB tables

    Requires Azure SQL Database:
      - sp_invoke_external_rest_endpoint
      - EXECUTE ANY EXTERNAL ENDPOINT permission on the calling user
*/
CREATE OR ALTER PROCEDURE dbo.Crm_ImportAll
    @DabEndpointUrl NVARCHAR(500)   -- e.g. 'https://ca-dab-api.kindpond-123.eastus.azurecontainerapps.io'
AS
BEGIN
    SET NOCOUNT ON;

    /* ═══════════════════════════════════════════════════════
       Step 1 – Build the GraphQL request
       
       DAB's GraphQL endpoint returns nested JSON:
         contacts → addresses  (one-to-many)
    ═══════════════════════════════════════════════════════ */

    DECLARE @url      NVARCHAR(4000) = @DabEndpointUrl + N'/graphql';
    DECLARE @payload  NVARCHAR(MAX)  = N'{
        "query": "{ contacts { items { ContactId FirstName LastName Email Phone SSN addresses { items { AddressId Street City State ZipCode } } } } }"
    }';
    DECLARE @headers  NVARCHAR(MAX) = N'{"Content-Type":"application/json"}';
    DECLARE @response NVARCHAR(MAX);
    DECLARE @retcode  INT;

    /* ═══════════════════════════════════════════════════════
       Step 2 – Call the DAB GraphQL endpoint
       
       sp_invoke_external_rest_endpoint returns:
       {
         "response": { "status": { "http": { "code": 200 } } },
         "result":   { ...the actual GraphQL response... }
       }

       @timeout = 120  allows for ACA cold-start (default is 30s)
    ═══════════════════════════════════════════════════════ */

    EXEC @retcode = sp_invoke_external_rest_endpoint
        @url      = @url,
        @method   = 'POST',
        @payload  = @payload,
        @headers  = @headers,
        @timeout  = 120,
        @response = @response OUTPUT;

    -- Verify HTTP 200
    IF @retcode <> 0 OR JSON_VALUE(@response, '$.response.status.http.code') <> '200'
    BEGIN
        DECLARE @errMsg NVARCHAR(500) = COALESCE(
            JSON_VALUE(@response, '$.response.status.http.description'),
            N'HTTP call failed with return code ' + CAST(@retcode AS NVARCHAR(10))
        );
        THROW 50001, @errMsg, 1;
    END

    /* ═══════════════════════════════════════════════════════
       Step 3 – Extract the GraphQL response body
       
       Actual data lives at:  $.result.data.contacts.items
    ═══════════════════════════════════════════════════════ */

    DECLARE @body NVARCHAR(MAX) = JSON_QUERY(@response, '$.result');

    /* ═══════════════════════════════════════════════════════
       Step 4 – Parse contacts from nested JSON
       
       OPENJSON shreds the items array.
       Each contact's "addresses" stays as raw JSON
       for the next step.
    ═══════════════════════════════════════════════════════ */

    SELECT
        ContactId,
        FirstName,
        LastName,
        Email,
        Phone,
        SSN,
        JSON_QUERY(addresses, '$.items') AS AddressesJson
    INTO #Contacts
    FROM OPENJSON(@body, '$.data.contacts.items') WITH (
        ContactId   INT             '$.ContactId',
        FirstName   NVARCHAR(100)   '$.FirstName',
        LastName    NVARCHAR(100)   '$.LastName',
        Email       NVARCHAR(200)   '$.Email',
        Phone       NVARCHAR(20)    '$.Phone',
        SSN         CHAR(11)        '$.SSN',
        addresses   NVARCHAR(MAX)   '$.addresses' AS JSON
    );

    /* ═══════════════════════════════════════════════════════
       Step 5 – Parse addresses (nested one-to-many)
       
       CROSS APPLY OPENJSON handles the nesting.
       Each contact's AddressesJson is shredded into rows.
    ═══════════════════════════════════════════════════════ */

    SELECT
        c.ContactId,
        a.AddressId,
        a.Street,
        a.City,
        a.[State],
        a.ZipCode
    INTO #Addresses
    FROM #Contacts c
    CROSS APPLY OPENJSON(c.AddressesJson) WITH (
        AddressId   INT             '$.AddressId',
        Street      NVARCHAR(200)   '$.Street',
        City        NVARCHAR(100)   '$.City',
        [State]     NVARCHAR(50)    '$.State',
        ZipCode     NVARCHAR(10)    '$.ZipCode'
    ) a;

    /* ═══════════════════════════════════════════════════════
       Step 6 – Clear and re-import (inside a transaction)
       
       Delete addresses first (FK dependency), then contacts.
       ImportedOn defaults to SYSUTCDATETIME() on insert.
       Transaction ensures we don't lose data on partial failure.
    ═══════════════════════════════════════════════════════ */

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM dbo.[Address];
        DELETE FROM dbo.Contact;

        INSERT INTO dbo.Contact (ContactId, FirstName, LastName, Email, Phone, SSN)
        SELECT ContactId, FirstName, LastName, Email, Phone, SSN
        FROM #Contacts;

        INSERT INTO dbo.[Address] (AddressId, ContactId, Street, City, [State], ZipCode)
        SELECT AddressId, ContactId, Street, City, [State], ZipCode
        FROM #Addresses;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    /* ═══════════════════════════════════════════════════════
       Step 7 – Report results
    ═══════════════════════════════════════════════════════ */

    SELECT
        (SELECT COUNT(*) FROM dbo.Contact)    AS ContactsImported,
        (SELECT COUNT(*) FROM dbo.[Address])  AS AddressesImported;

    DROP TABLE #Contacts;
    DROP TABLE #Addresses;
END
GO
