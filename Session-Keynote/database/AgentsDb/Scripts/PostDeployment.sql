-- Seed: Categories (copied from sibling CatalogDb)
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

-- Seed: Products (copied from sibling CatalogDb + Cost/Inventory added)
IF NOT EXISTS (SELECT 1 FROM [dbo].[Product])
BEGIN
    SET IDENTITY_INSERT [dbo].[Product] ON;
    INSERT INTO [dbo].[Product] ([ProductId], [Name], [CategoryId], [Price], [Cost], [Inventory])
    VALUES
        (1,  N'USS Enterprise NCC-1701',         1, 149.99,  62.00, 45),
        (2,  N'USS Enterprise NCC-1701-D',       1,  89.99,  38.00, 80),
        (3,  N'USS Defiant NX-74205',            1,  64.99,  28.00, 60),
        (4,  N'USS Voyager NCC-74656',           1,  79.99,  34.00, 55),
        (5,  N'USS Enterprise NCC-1701-E',       1,  99.99,  42.00, 35),
        (6,  N'Klingon Bird-of-Prey',            2,  59.99,  45.00, 120),  -- doomed: high cost ratio + dying sales
        (7,  N'Klingon Vor''cha Attack Cruiser', 2,  74.99,  30.00, 40),
        (8,  N'Romulan D''deridex Warbird',      3, 109.99,  48.00, 30),
        (9,  N'Borg Cube',                       4, 129.99,  55.00, 90),   -- doomed: high return rate
        (10, N'Deep Space Nine',                 5, 189.99,  75.00, 20);
    SET IDENTITY_INSERT [dbo].[Product] OFF;
END

-- Seed: SalesHistory (~2000 rows, last 24 months)
-- Product 6 (Bird-of-Prey): sales drop to 0-1 in last 6 months
-- Product 9 (Borg Cube): ~30% return rate
IF NOT EXISTS (SELECT 1 FROM [dbo].[SalesHistory])
BEGIN
    DECLARE @i INT = 0;
    DECLARE @productId INT;
    DECLARE @saleDate DATE;
    DECLARE @unitsSold INT;
    DECLARE @unitPrice DECIMAL(10,2);
    DECLARE @returnFlag BIT;
    DECLARE @monthsAgo INT;
    DECLARE @rand FLOAT;
    DECLARE @listPrice DECIMAL(10,2);

    WHILE @i < 2000
    BEGIN
        SET @rand = RAND(CHECKSUM(NEWID()));
        SET @productId = 1 + ABS(CHECKSUM(NEWID())) % 10;
        SET @monthsAgo = ABS(CHECKSUM(NEWID())) % 24;
        SET @saleDate = DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 730), GETDATE());

        SELECT @listPrice = [Price] FROM [dbo].[Product] WHERE [ProductId] = @productId;
        SET @unitPrice = @listPrice - (@listPrice * 0.05 * (ABS(CHECKSUM(NEWID())) % 3));

        -- Default: healthy product
        SET @unitsSold = 3 + ABS(CHECKSUM(NEWID())) % 10;
        SET @returnFlag = CASE WHEN ABS(CHECKSUM(NEWID())) % 20 = 0 THEN 1 ELSE 0 END;

        -- Product 6 (Bird-of-Prey): sales collapse in last 6 months
        IF @productId = 6
        BEGIN
            IF @saleDate > DATEADD(MONTH, -6, GETDATE())
                SET @unitsSold = ABS(CHECKSUM(NEWID())) % 2;  -- 0 or 1
            ELSE
                SET @unitsSold = 2 + ABS(CHECKSUM(NEWID())) % 5;
        END

        -- Product 9 (Borg Cube): ~30% return rate
        IF @productId = 9
            SET @returnFlag = CASE WHEN ABS(CHECKSUM(NEWID())) % 10 < 3 THEN 1 ELSE 0 END;

        INSERT INTO [dbo].[SalesHistory] ([ProductId], [SaleDate], [UnitsSold], [UnitPrice], [ReturnFlag])
        VALUES (@productId, @saleDate, @unitsSold, @unitPrice, @returnFlag);

        SET @i = @i + 1;
    END
END
