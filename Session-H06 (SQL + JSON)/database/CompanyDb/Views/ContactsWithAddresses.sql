CREATE VIEW [dbo].[ContactsWithAddresses]
AS
SELECT
    c.ContactId,
    c.FirstName,
    c.LastName,
    c.Email,
    c.Phone,
    c.ImportedOn  AS ContactImportedOn,
    a.AddressId,
    a.Street,
    a.City,
    a.[State],
    a.ZipCode,
    a.ImportedOn  AS AddressImportedOn
FROM dbo.Contact c
LEFT JOIN dbo.[Address] a ON c.ContactId = a.ContactId;
