CREATE TABLE [dbo].[Categories]
(
    [CategoryId] INT NOT NULL PRIMARY KEY IDENTITY(1,1),
    [Name] NVARCHAR(100) NOT NULL,
    [Description] NVARCHAR(500) NULL
);
