CREATE TABLE [dbo].[Review]
(
    [ReviewId]    INT            NOT NULL PRIMARY KEY IDENTITY(1,1),
    [ProductId]   INT            NOT NULL,
    [CustomerId]  INT            NOT NULL,
    [ReviewDate]  DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    [ReviewText]  NVARCHAR(MAX)  NOT NULL,
    CONSTRAINT [FK_Review_Product]  FOREIGN KEY ([ProductId])  REFERENCES [dbo].[Product]([ProductId]),
    CONSTRAINT [FK_Review_Customer] FOREIGN KEY ([CustomerId]) REFERENCES [dbo].[Customer]([CustomerId])
);
