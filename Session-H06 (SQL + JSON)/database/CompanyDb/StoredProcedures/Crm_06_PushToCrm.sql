/*
    Crm_06_PushToCrm
    ────────────────
    Builds JSON from CompanyDb and PATCHes a single contact back
    to CrmDb via the DAB REST endpoint.

    Shows: relational → JSON → sp_invoke_external_rest_endpoint → REST PATCH.

    EXEC dbo.Crm_06_PushToCrm
        @DabEndpointUrl = 'https://...',
        @ContactId      = 1;
*/
CREATE OR ALTER PROCEDURE dbo.Crm_06_PushToCrm
    @DabEndpointUrl NVARCHAR(500),
    @ContactId      INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Contact WHERE ContactId = @ContactId)
    BEGIN
        DECLARE @notFound NVARCHAR(200) = N'ContactId ' + CAST(@ContactId AS NVARCHAR(10)) + N' not found in CompanyDb.';
        THROW 50006, @notFound, 1;
    END

    -- Step 1: Build JSON from relational data (FOR JSON PATH)
    DECLARE @payload NVARCHAR(MAX);
    SELECT @payload = (
        SELECT
            FirstName,
            LastName,
            Email,
            Phone
        FROM dbo.Contact
        WHERE ContactId = @ContactId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    PRINT 'JSON payload: ' + @payload;

    -- Step 2: PATCH to DAB REST endpoint  /api/Contact/ContactId/{id}
    DECLARE @url      NVARCHAR(4000) = @DabEndpointUrl
                        + N'/api/Contact/ContactId/'
                        + CAST(@ContactId AS NVARCHAR(10));
    DECLARE @headers  NVARCHAR(MAX) = N'{"Content-Type":"application/json"}';
    DECLARE @response NVARCHAR(MAX);
    DECLARE @retcode  INT;

    EXEC @retcode = sp_invoke_external_rest_endpoint
        @url      = @url,
        @method   = 'PATCH',
        @payload  = @payload,
        @headers  = @headers,
        @timeout  = 120,
        @response = @response OUTPUT;

    IF @retcode <> 0 OR JSON_VALUE(@response, '$.response.status.http.code') <> '200'
    BEGIN
        DECLARE @errMsg NVARCHAR(500) = COALESCE(
            JSON_VALUE(@response, '$.response.status.http.description'),
            N'REST PATCH failed with return code ' + CAST(@retcode AS NVARCHAR(10))
        );
        THROW 50006, @errMsg, 1;
    END

    -- Step 3: Show the updated record as returned by DAB
    SELECT
        @ContactId                                                              AS ContactId,
        JSON_VALUE(@response, '$.result.value[0].FirstName')                    AS FirstName,
        JSON_VALUE(@response, '$.result.value[0].LastName')                     AS LastName,
        JSON_VALUE(@response, '$.result.value[0].Email')                        AS Email,
        JSON_VALUE(@response, '$.result.value[0].Phone')                        AS Phone,
        N'Updated in CRM via REST PATCH'                                        AS Status;
END
GO
