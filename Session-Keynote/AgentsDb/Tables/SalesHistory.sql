CREATE TABLE [dbo].[SalesHistory]
(
    [Id] INT NOT NULL PRIMARY KEY IDENTITY(1,1),
    [ProductId] INT NOT NULL,
    [SaleDate] DATE NOT NULL,
    [UnitsSold] INT NOT NULL,
    [UnitPrice] DECIMAL(10,2) NOT NULL,
    [ReturnFlag] BIT NOT NULL DEFAULT 0,
    CONSTRAINT [FK_SalesHistory_Product] FOREIGN KEY ([ProductId]) REFERENCES [dbo].[Product]([ProductId])
);
