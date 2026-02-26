-- Seed data for Star Trek Ship Model Store - InventoryDb

SET IDENTITY_INSERT [dbo].[Warehouses] ON;

INSERT INTO [dbo].[Warehouses] ([WarehouseId], [Name], [Location])
VALUES
    (1, N'Utopia Planitia', N'Mars'),
    (2, N'San Francisco Fleet Yards', N'Earth'),
    (3, N'Starbase 74', N'Tarsas III Orbit');

SET IDENTITY_INSERT [dbo].[Warehouses] OFF;

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
