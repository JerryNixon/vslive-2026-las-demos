CREATE TABLE [dbo].[Customer]
(
    [CustomerId] INT NOT NULL PRIMARY KEY IDENTITY(1,1),
    [FirstName]  NVARCHAR(100) NOT NULL,
    [LastName]   NVARCHAR(100) NOT NULL,
    [Email]      NVARCHAR(200) NULL
);
