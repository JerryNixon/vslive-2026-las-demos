/*
    Crm_RunAll
    ──────────
    Runs all four demo steps in sequence.
    Equivalent to the original Crm_ImportAll but with visibility at each step.

    EXEC dbo.Crm_RunAll
        @DabEndpointUrl = 'https://ca-dab-api.wonderfulplant-f63acab2.westus2.azurecontainerapps.io',
        @First = 3;
*/
CREATE OR ALTER PROCEDURE dbo.Crm_RunAll
    @DabEndpointUrl NVARCHAR(500),
    @First          INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '══════════════════════════════════════';
    PRINT '  Step 1: Fetch from CRM via GraphQL';
    PRINT '══════════════════════════════════════';
    EXEC dbo.Crm_01_Fetch @DabEndpointUrl = @DabEndpointUrl, @First = @First;

    PRINT '';
    PRINT '══════════════════════════════════════';
    PRINT '  Step 2: Parse contacts (OPENJSON)';
    PRINT '══════════════════════════════════════';
    EXEC dbo.Crm_02_ParseContacts;

    PRINT '';
    PRINT '══════════════════════════════════════';
    PRINT '  Step 3: Parse addresses (CROSS APPLY)';
    PRINT '══════════════════════════════════════';
    EXEC dbo.Crm_03_ParseAddresses;

    PRINT '';
    PRINT '══════════════════════════════════════';
    PRINT '  Step 4: Import into CompanyDb (MERGE)';
    PRINT '══════════════════════════════════════';
    EXEC dbo.Crm_04_Import;
END
GO
