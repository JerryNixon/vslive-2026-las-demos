-- Register the Azure OpenAI text-embedding-3-large deployment as an external model

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Str0ngMK#2026!';
GO

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = 'text-embedding-3-large')
    DROP EXTERNAL MODEL [text-embedding-3-large];
GO

IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = '$(OPENAI_ENDPOINT)/')
    DROP DATABASE SCOPED CREDENTIAL [$(OPENAI_ENDPOINT)/];
GO

-- Credential name MUST be the endpoint URL for sp_invoke_external_rest_endpoint
CREATE DATABASE SCOPED CREDENTIAL [$(OPENAI_ENDPOINT)/]
WITH IDENTITY = 'HTTPEndpointHeaders',
SECRET = '{"api-key":"$(OPENAI_KEY)"}';  -- replaced at deploy time by azure-up.ps1
GO

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = 'text-embedding-3-large')
    DROP EXTERNAL MODEL [text-embedding-3-large];
GO

CREATE EXTERNAL MODEL [text-embedding-3-large]
WITH (
    LOCATION = '$(OPENAI_ENDPOINT)/openai/deployments/text-embedding-3-large/embeddings?api-version=2024-02-01',
    API_FORMAT = 'OpenAI',
    MODEL = 'text-embedding-3-large',
    CREDENTIAL = [$(OPENAI_ENDPOINT)/],
    MODEL_TYPE = EMBEDDINGS
);
GO
