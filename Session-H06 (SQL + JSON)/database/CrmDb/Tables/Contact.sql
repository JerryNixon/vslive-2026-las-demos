CREATE TABLE [dbo].[Contact]
(
    [ContactId]  INT            NOT NULL PRIMARY KEY IDENTITY(1,1),
    [FirstName]  NVARCHAR(100)  NOT NULL,
    [LastName]   NVARCHAR(100)  NOT NULL,
    [Email]      NVARCHAR(200)  NULL,
    [Phone]      NVARCHAR(20)   NULL,
    [SSN]        CHAR(11)       NULL
);
