-- Seed data for Star Trek Ship Model Store - InventoryDb

IF NOT EXISTS (SELECT 1 FROM [dbo].[Warehouse])
BEGIN
    SET IDENTITY_INSERT [dbo].[Warehouse] ON;

    INSERT INTO [dbo].[Warehouse] ([WarehouseId], [Name], [Location])
    VALUES
        (1, N'Dallas Distribution Center', N'Texas'),
        (2, N'Atlanta Fulfillment Hub', N'Georgia'),
        (3, N'Portland Warehouse', N'Oregon');

    SET IDENTITY_INSERT [dbo].[Warehouse] OFF;
END

IF NOT EXISTS (SELECT 1 FROM [dbo].[Inventory])
BEGIN
    SET IDENTITY_INSERT [dbo].[Inventory] ON;

    INSERT INTO [dbo].[Inventory] ([InventoryId], [ProductId], [WarehouseId], [Quantity])
    VALUES
        (1,  1,  1, 12),
        (2,  2,  1, 8),
        (3,  3,  2, 25),
        (4,  4,  2, 15),
        (5,  5,  1, 6),
        (6,  6,  3, 30),
        (7,  7,  3, 10),
        (8,  8,  2, 5),
        (9,  9,  1, 3),
        (10, 10, 3, 2);

    SET IDENTITY_INSERT [dbo].[Inventory] OFF;
END
