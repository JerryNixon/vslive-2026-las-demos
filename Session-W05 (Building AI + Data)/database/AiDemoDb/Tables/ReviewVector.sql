IF OBJECT_ID('dbo.ReviewVector', 'U') IS NULL
CREATE TABLE [dbo].[ReviewVector]
(
    [Id]        INT            NOT NULL PRIMARY KEY IDENTITY(1,1),
    [ReviewId]  INT            NOT NULL,
    [Chunk]     NVARCHAR(MAX)  NULL,
    [Embedding] VECTOR(1536)   NULL,
    CONSTRAINT [FK_ReviewVector_Review] FOREIGN KEY ([ReviewId]) REFERENCES [dbo].[Review]([ReviewId])
);
