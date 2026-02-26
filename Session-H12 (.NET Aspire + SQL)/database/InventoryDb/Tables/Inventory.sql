CREATE TABLE [dbo].[Inventory]
(
    [InventoryId] INT NOT NULL PRIMARY KEY IDENTITY(1,1),
    [ProductId] INT NOT NULL,
    [WarehouseId] INT NOT NULL,
    [Quantity] INT NOT NULL DEFAULT 0,
    CONSTRAINT [FK_Inventory_Warehouse] FOREIGN KEY ([WarehouseId]) REFERENCES [dbo].[Warehouse]([WarehouseId])
);
