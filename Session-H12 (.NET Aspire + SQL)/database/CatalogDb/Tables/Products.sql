CREATE TABLE [dbo].[Products]
(
    [ProductId] INT NOT NULL PRIMARY KEY IDENTITY(1,1),
    [Name] NVARCHAR(200) NOT NULL,
    [CategoryId] INT NOT NULL,
    [Scale] NVARCHAR(50) NOT NULL,
    [Price] DECIMAL(10,2) NOT NULL,
    [Description] NVARCHAR(1000) NULL,
    CONSTRAINT [FK_Products_Categories] FOREIGN KEY ([CategoryId]) REFERENCES [dbo].[Categories]([CategoryId])
);
