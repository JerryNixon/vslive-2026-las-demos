/*
    CrmRawJson – staging table for the raw GraphQL response.
    
    Crm_01_Fetch writes here.
    All other demo procs read from here.
    Only one row ever exists (truncated on each fetch).
*/
CREATE TABLE dbo.CrmRawJson
(
    Id          INT            NOT NULL DEFAULT 1 PRIMARY KEY CHECK (Id = 1),
    FetchedOn   DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    RawJson     NVARCHAR(MAX)  NOT NULL
);
