/*
    Crm_01_Fetch
    ────────────
    Calls DAB's GraphQL endpoint and stores the raw JSON in dbo.CrmRawJson.
    All subsequent Crm_* procs read from that staging table.

    EXEC dbo.Crm_01_Fetch @DabEndpointUrl = 'https://...', @First = 3;
*/
CREATE OR ALTER PROCEDURE dbo.Crm_01_Fetch
    @DabEndpointUrl NVARCHAR(500),
    @First          INT = NULL          -- NULL = all contacts
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @gql NVARCHAR(500) = CASE
        WHEN @First IS NOT NULL
        THEN N'{ contacts(first: ' + CAST(@First AS NVARCHAR(10)) + N') { items { ContactId FirstName LastName Email Phone SSN addresses { items { AddressId Street City State ZipCode } } } } }'
        ELSE N'{ contacts { items { ContactId FirstName LastName Email Phone SSN addresses { items { AddressId Street City State ZipCode } } } } }'
    END;

    DECLARE @url      NVARCHAR(4000) = @DabEndpointUrl + N'/graphql';
    DECLARE @payload  NVARCHAR(MAX)  = N'{"query": "' + @gql + N'"}';
    DECLARE @headers  NVARCHAR(MAX)  = N'{"Content-Type":"application/json"}';
    DECLARE @response NVARCHAR(MAX);
    DECLARE @retcode  INT;

    EXEC @retcode = sp_invoke_external_rest_endpoint
        @url      = @url,
        @method   = 'POST',
        @payload  = @payload,
        @headers  = @headers,
        @timeout  = 120,
        @response = @response OUTPUT;

    IF @retcode <> 0 OR JSON_VALUE(@response, '$.response.status.http.code') <> '200'
    BEGIN
        DECLARE @errMsg NVARCHAR(500) = COALESCE(
            JSON_VALUE(@response, '$.response.status.http.description'),
            N'HTTP call failed with return code ' + CAST(@retcode AS NVARCHAR(10))
        );
        THROW 50001, @errMsg, 1;
    END

    DECLARE @body NVARCHAR(MAX) = JSON_QUERY(@response, '$.result');

    TRUNCATE TABLE dbo.CrmRawJson;
    INSERT INTO dbo.CrmRawJson (RawJson) VALUES (@body);

    -- Show what we stored
    SELECT FetchedOn, LEFT(RawJson, 500) AS JsonPreview FROM dbo.CrmRawJson;
END
GO
