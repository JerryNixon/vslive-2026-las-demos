CREATE TABLE [dbo].[Warehouse]
(
    [WarehouseId] INT NOT NULL PRIMARY KEY IDENTITY(1,1),
    [Name] NVARCHAR(100) NOT NULL,
    [Location] NVARCHAR(200) NOT NULL
);
