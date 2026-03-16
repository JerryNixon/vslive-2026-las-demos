CREATE TABLE [dbo].[Address]
(
    [AddressId]  INT            NOT NULL PRIMARY KEY,  -- imported from CRM (no identity)
    [ContactId]  INT            NOT NULL,
    [Street]     NVARCHAR(200)  NOT NULL,
    [City]       NVARCHAR(100)  NOT NULL,
    [State]      NVARCHAR(50)   NOT NULL,
    [ZipCode]    NVARCHAR(10)   NOT NULL,
    [ImportedOn] DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT [FK_Address_Contact] FOREIGN KEY ([ContactId]) REFERENCES [dbo].[Contact]([ContactId])
);
