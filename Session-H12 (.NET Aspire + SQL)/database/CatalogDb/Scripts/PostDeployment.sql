-- Seed data for Star Trek Ship Model Store - CatalogDb

SET IDENTITY_INSERT [dbo].[Categories] ON;

INSERT INTO [dbo].[Categories] ([CategoryId], [Name], [Description])
VALUES
    (1, N'Federation Starships', N'United Federation of Planets vessels'),
    (2, N'Klingon Warships', N'Klingon Empire military vessels'),
    (3, N'Romulan Vessels', N'Romulan Star Empire ships'),
    (4, N'Borg Cubes', N'Borg Collective vessels'),
    (5, N'Space Stations', N'Orbital stations and starbases');

SET IDENTITY_INSERT [dbo].[Categories] OFF;

SET IDENTITY_INSERT [dbo].[Products] ON;

INSERT INTO [dbo].[Products] ([ProductId], [Name], [CategoryId], [Scale], [Price], [Description])
VALUES
    (1,  N'USS Enterprise NCC-1701',       1, N'1:350',  149.99, N'Constitution-class starship — The Original Series'),
    (2,  N'USS Enterprise NCC-1701-D',     1, N'1:1400', 89.99,  N'Galaxy-class starship — The Next Generation'),
    (3,  N'USS Defiant NX-74205',          1, N'1:1000', 64.99,  N'Defiant-class escort — Deep Space Nine'),
    (4,  N'USS Voyager NCC-74656',         1, N'1:1400', 79.99,  N'Intrepid-class starship — Voyager'),
    (5,  N'USS Enterprise NCC-1701-E',     1, N'1:1400', 99.99,  N'Sovereign-class starship — First Contact'),
    (6,  N'Klingon Bird-of-Prey',          2, N'1:1000', 59.99,  N'B''rel-class scout vessel'),
    (7,  N'Klingon Vor''cha Attack Cruiser', 2, N'1:1400', 74.99, N'Vor''cha-class attack cruiser'),
    (8,  N'Romulan D''deridex Warbird',    3, N'1:2500', 109.99, N'D''deridex-class warbird'),
    (9,  N'Borg Cube',                     4, N'1:5000', 129.99, N'Standard Borg cube vessel'),
    (10, N'Deep Space Nine',               5, N'1:2500', 189.99, N'Cardassian-built orbital station');

SET IDENTITY_INSERT [dbo].[Products] OFF;
