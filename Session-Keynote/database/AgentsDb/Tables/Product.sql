CREATE TABLE [dbo].[Product]
(
    [ProductId] INT NOT NULL PRIMARY KEY IDENTITY(1,1),
    [Name] NVARCHAR(200) NOT NULL,
    [CategoryId] INT NOT NULL,
    [Price] DECIMAL(10,2) NOT NULL,
    [Cost] DECIMAL(10,2) NOT NULL,
    [Inventory] INT NOT NULL DEFAULT 0,
    CONSTRAINT [FK_Product_Category] FOREIGN KEY ([CategoryId]) REFERENCES [dbo].[Category]([CategoryId])
);
