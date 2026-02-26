-- Seed data for Star Trek Ship Model Store - CatalogDb

IF NOT EXISTS (SELECT 1 FROM [dbo].[Category])
BEGIN
    SET IDENTITY_INSERT [dbo].[Category] ON;

    INSERT INTO [dbo].[Category] ([CategoryId], [Name])
    VALUES
        (1, N'Federation Starships'),
        (2, N'Klingon Warships'),
        (3, N'Romulan Vessels'),
        (4, N'Borg Cubes'),
        (5, N'Space Stations');

    SET IDENTITY_INSERT [dbo].[Category] OFF;
END

IF NOT EXISTS (SELECT 1 FROM [dbo].[Product])
BEGIN
    SET IDENTITY_INSERT [dbo].[Product] ON;

    INSERT INTO [dbo].[Product] ([ProductId], [Name], [CategoryId], [Price])
    VALUES
        (1,  N'USS Enterprise NCC-1701',         1, 149.99),
        (2,  N'USS Enterprise NCC-1701-D',       1, 89.99),
        (3,  N'USS Defiant NX-74205',            1, 64.99),
        (4,  N'USS Voyager NCC-74656',           1, 79.99),
        (5,  N'USS Enterprise NCC-1701-E',       1, 99.99),
        (6,  N'Klingon Bird-of-Prey',            2, 59.99),
        (7,  N'Klingon Vor''cha Attack Cruiser', 2, 74.99),
        (8,  N'Romulan D''deridex Warbird',      3, 109.99),
        (9,  N'Borg Cube',                       4, 129.99),
        (10, N'Deep Space Nine',                 5, 189.99);

    SET IDENTITY_INSERT [dbo].[Product] OFF;
END
