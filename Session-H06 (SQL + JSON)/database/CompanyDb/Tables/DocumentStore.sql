CREATE TABLE [dbo].[DocumentStore]
(
    [Id]           INT            NOT NULL PRIMARY KEY IDENTITY(1,1),
    [DocumentType] NVARCHAR(50)   NOT NULL,
    [Data]         JSON           NOT NULL,

    -- Computed column: extract a property from inside the JSON
    [DisplayName]  AS CAST(JSON_VALUE([Data], '$.name') AS NVARCHAR(200)),

    -- Constraint: $.name must exist in every document
    CONSTRAINT CK_DocumentStore_NameRequired
        CHECK (JSON_VALUE([Data], '$.name') IS NOT NULL),

    -- Constraint: if $.email is present, it must look like an email (LIKE = T-SQL regex)
    CONSTRAINT CK_DocumentStore_ValidEmail
        CHECK (JSON_VALUE([Data], '$.email') IS NULL
               OR JSON_VALUE([Data], '$.email') LIKE '%_@_%.__%')
);
GO

-- Index on the computed column (JSON property → index)
CREATE INDEX IX_DocumentStore_DisplayName
    ON [dbo].[DocumentStore] ([DisplayName]);
GO
