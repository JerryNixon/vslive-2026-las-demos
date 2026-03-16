CREATE TABLE [dbo].[Contact]
(
    [ContactId]  INT            NOT NULL PRIMARY KEY,  -- imported from CRM (no identity)
    [FirstName]  NVARCHAR(100)  NOT NULL,
    [LastName]   NVARCHAR(100)  NOT NULL,
    [Email]      NVARCHAR(200)  NULL,
    [Phone]      NVARCHAR(20)   NULL,
    [SSN]        CHAR(11)       NULL,                  -- masked value from CRM
    [ImportedOn] DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);
