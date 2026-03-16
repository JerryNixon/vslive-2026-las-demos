-- CrmDb Post-Deployment Script
-- Seed data: 50 Star Trek contacts with 61 addresses
-- Idempotent: safe to run on existing data

IF NOT EXISTS (SELECT 1 FROM dbo.Contact WHERE ContactId = 1)
BEGIN

SET IDENTITY_INSERT dbo.Contact ON;

INSERT INTO dbo.Contact (ContactId, FirstName, LastName, Email, Phone, SSN) VALUES
(1,  'James',        'Kirk',         'jkirk@starfleet.org',       '555-0001',  '123-45-6789'),
(2,  'Spock',        'Grayson',      'spock@starfleet.org',       '555-0002',  '234-56-7890'),
(3,  'Leonard',      'McCoy',        'lmccoy@starfleet.org',      '555-0003',  '345-67-8901'),
(4,  'Montgomery',   'Scott',        'mscott@starfleet.org',      '555-0004',  '456-78-9012'),
(5,  'Nyota',        'Uhura',        'nuhura@starfleet.org',      '555-0005',  '567-89-1234'),
(6,  'Hikaru',       'Sulu',         'hsulu@starfleet.org',       '555-0006',  '678-91-2345'),
(7,  'Pavel',        'Chekov',       'pchekov@starfleet.org',     '555-0007',  '789-12-3456'),
(8,  'Christine',    'Chapel',       'cchapel@starfleet.org',     '555-0008',  '891-23-4567'),
(9,  'Janice',       'Rand',         'jrand@starfleet.org',       '555-0009',  '912-34-5678'),
(10, 'Jean-Luc',     'Picard',       'jpicard@starfleet.org',     '555-0010',  '135-46-7891'),
(11, 'William',      'Riker',        'wriker@starfleet.org',      '555-0011',  '246-57-8912'),
(12, 'Data',         'Soong',        'dsoong@starfleet.org',      '555-0012',  '357-68-9123'),
(13, 'Deanna',       'Troi',         'dtroi@starfleet.org',       '555-0013',  '468-79-1235'),
(14, 'Worf',         'Mogh',         'wmogh@starfleet.org',       '555-0014',  '579-81-2346'),
(15, 'Geordi',       'LaForge',      'glaforge@starfleet.org',    '555-0015',  '681-92-3457'),
(16, 'Beverly',      'Crusher',      'bcrusher@starfleet.org',    '555-0016',  '792-13-4568'),
(17, 'Wesley',       'Crusher',      'wcrusher@starfleet.org',    '555-0017',  '813-24-5679'),
(18, 'Benjamin',     'Sisko',        'bsisko@starfleet.org',      '555-0018',  '524-35-6781'),
(19, 'Kira',         'Nerys',        'knerys@starfleet.org',      '555-0019',  '136-47-7892'),
(20, 'Odo',          'Changeling',   'odo@starfleet.org',         '555-0020',  '247-58-8913'),
(21, 'Julian',       'Bashir',       'jbashir@starfleet.org',     '555-0021',  '358-69-9124'),
(22, 'Jadzia',       'Dax',          'jdax@starfleet.org',        '555-0022',  '469-71-1236'),
(23, 'Miles',        'OBrien',       'mobrien@starfleet.org',     '555-0023',  '571-82-2347'),
(24, 'Quark',        'Ferengi',      'quark@starfleet.org',       '555-0024',  '682-93-3458'),
(25, 'Kathryn',      'Janeway',      'kjaneway@starfleet.org',    '555-0025',  '793-14-4569'),
(26, 'Chakotay',     'Dorvan',       'chakotay@starfleet.org',    '555-0026',  '814-25-5671'),
(27, 'Tuvok',        'Vulcan',       'tuvok@starfleet.org',       '555-0027',  '425-36-6782'),
(28, 'Tom',          'Paris',        'tparis@starfleet.org',      '555-0028',  '137-48-7893'),
(29, 'BElanna',      'Torres',       'btorres@starfleet.org',     '555-0029',  '248-59-8914'),
(30, 'Harry',        'Kim',          'hkim@starfleet.org',        '555-0030',  '359-61-9125'),
(31, 'Seven',        'Hansen',       'shansen@starfleet.org',     '555-0031',  '461-72-1237'),
(32, 'Neelix',       'Talax',        'neelix@starfleet.org',      '555-0032',  '572-83-2348'),
(33, 'Jonathan',     'Archer',       'jarcher@starfleet.org',     '555-0033',  '683-94-3459'),
(34, 'TPol',         'Vulcan',       'tpol@starfleet.org',        '555-0034',  '794-15-4561'),
(35, 'Trip',         'Tucker',       'ttucker@starfleet.org',     '555-0035',  '815-26-5672'),
(36, 'Hoshi',        'Sato',         'hsato@starfleet.org',       '555-0036',  '326-37-6783'),
(37, 'Malcolm',      'Reed',         'mreed@starfleet.org',       '555-0037',  '138-49-7894'),
(38, 'Travis',       'Mayweather',   'tmayweather@starfleet.org', '555-0038',  '249-51-8915'),
(39, 'Michael',      'Burnham',      'mburnham@starfleet.org',    '555-0039',  '351-62-9126'),
(40, 'Saru',         'Kelpien',      'saru@starfleet.org',        '555-0040',  '462-73-1238'),
(41, 'Sylvia',       'Tilly',        'stilly@starfleet.org',      '555-0041',  '573-84-2349'),
(42, 'Paul',         'Stamets',      'pstamets@starfleet.org',    '555-0042',  '684-95-3451'),
(43, 'Hugh',         'Culber',       'hculber@starfleet.org',     '555-0043',  '795-16-4562'),
(44, 'Christopher',  'Pike',         'cpike@starfleet.org',       '555-0044',  '816-27-5673'),
(45, 'Una',          'Chin-Riley',   'uchinriley@starfleet.org',  '555-0045',  '427-38-6784'),
(46, 'Beckett',      'Mariner',      'bmariner@starfleet.org',    '555-0046',  '139-41-7895'),
(47, 'Brad',         'Boimler',      'bboimler@starfleet.org',    '555-0047',  '241-52-8916'),
(48, 'Carol',        'Freeman',      'cfreeman@starfleet.org',    '555-0048',  '352-63-9127'),
(49, 'DAltan',       'Ransom',       'dransom@starfleet.org',     '555-0049',  '463-74-1239'),
(50, 'Sam',          'Rutherford',   'srutherford@starfleet.org', '555-0050',  '574-85-2341');

SET IDENTITY_INSERT dbo.Contact OFF;

SET IDENTITY_INSERT dbo.[Address] ON;

INSERT INTO dbo.[Address] (AddressId, ContactId, Street, City, [State], ZipCode) VALUES
-- Kirk (2 addresses)
(1,  1,  '742 Riverside Dr',         'Riverside',        'Iowa',           '52327'),
(2,  1,  '1 Starfleet Plaza',        'San Francisco',    'California',     '94102'),
-- Spock
(3,  2,  '47 Vulcan Way',            'San Francisco',    'California',     '94105'),
-- McCoy (2 addresses)
(4,  3,  '221 Peachtree St',         'Atlanta',          'Georgia',        '30303'),
(5,  3,  '88 Medical Row',           'San Francisco',    'California',     '94109'),
-- Scott
(6,  4,  '512 Engineering Blvd',     'Houston',          'Texas',          '77001'),
-- Uhura
(7,  5,  '900 Sunset Blvd',          'Los Angeles',      'California',     '90028'),
-- Sulu
(8,  6,  '333 Helm St',              'San Francisco',    'California',     '94117'),
-- Chekov
(9,  7,  '77 Lake Shore Dr',         'Chicago',          'Illinois',       '60601'),
-- Chapel
(10, 8,  '45 Beacon Hill Rd',        'Boston',           'Massachusetts',  '02108'),
-- Rand
(11, 9,  '628 Pike Place',           'Seattle',          'Washington',     '98101'),
-- Picard (2 addresses)
(12, 10, '1701 Walnut St',           'Philadelphia',     'Pennsylvania',   '19103'),
(13, 10, '25 Harvard Yard',          'Boston',           'Massachusetts',  '02138'),
-- Riker (2 addresses)
(14, 11, '200 Northern Lights Ave',  'Anchorage',        'Alaska',         '99501'),
(15, 11, '15 Marina Blvd',           'San Francisco',    'California',     '94123'),
-- Data
(16, 12, '404 Silicon Valley Rd',    'San Jose',         'California',     '95112'),
-- Troi
(17, 13, '777 Casino Blvd',          'Las Vegas',        'Nevada',         '89101'),
-- Worf
(18, 14, '100 Mountain View Dr',     'Denver',           'Colorado',       '80202'),
-- LaForge
(19, 15, '250 Motor City Ln',        'Detroit',          'Michigan',       '48201'),
-- Beverly Crusher
(20, 16, '800 Medical Center Dr',    'Philadelphia',     'Pennsylvania',   '19104'),
-- Wesley
(21, 17, '55 Desert Star Rd',        'Phoenix',          'Arizona',        '85001'),
-- Sisko (2 addresses)
(22, 18, '455 Bourbon St',           'New Orleans',      'Louisiana',      '70112'),
(23, 18, '1 Times Square',           'New York',         'New York',       '10036'),
-- Kira
(24, 19, '310 Rose Garden Ln',       'Portland',         'Oregon',         '97201'),
-- Odo
(25, 20, '175 Temple Sq',            'Salt Lake City',   'Utah',           '84101'),
-- Bashir
(26, 21, '600 Ocean Dr',             'Miami',            'Florida',        '33139'),
-- Dax
(27, 22, '222 Congress Ave',         'Austin',           'Texas',          '78701'),
-- O'Brien (2 addresses)
(28, 23, '450 Elm St',               'Dallas',           'Texas',          '75201'),
(29, 23, '120 Main St',              'Fort Worth',       'Texas',          '76102'),
-- Quark
(30, 24, '888 Strip Blvd',           'Las Vegas',        'Nevada',         '89109'),
-- Janeway (2 addresses)
(31, 25, '300 College Ave',          'Bloomington',      'Indiana',        '47401'),
(32, 25, '50 Command Way',           'San Francisco',    'California',     '94129'),
-- Chakotay
(33, 26, '150 Turquoise Trail',      'Santa Fe',         'New Mexico',     '87501'),
-- Tuvok
(34, 27, '275 Pacific Coast Hwy',    'San Diego',        'California',     '92101'),
-- Paris
(35, 28, '440 Music Row',            'Nashville',        'Tennessee',      '37203'),
-- Torres
(36, 29, '700 Queen Anne Ave',       'Seattle',          'Washington',     '98109'),
-- Kim
(37, 30, '125 Capitol Mall',         'Sacramento',       'California',     '95814'),
-- Seven
(38, 31, '350 Nicollet Ave',         'Minneapolis',      'Minnesota',      '55401'),
-- Neelix
(39, 32, '500 International Dr',     'Orlando',          'Florida',        '32819'),
-- Archer
(40, 33, '1 Central Park W',         'New York',         'New York',       '10023'),
-- T'Pol
(41, 34, '88 Speedway Blvd',         'Tucson',           'Arizona',        '85701'),
-- Tucker (2 addresses)
(42, 35, '325 Beach Blvd',           'Jacksonville',     'Florida',        '32250'),
(43, 35, '610 Theme Park Dr',        'Orlando',          'Florida',        '32801'),
-- Sato
(44, 36, '90 High St',               'Columbus',         'Ohio',           '43215'),
-- Reed
(45, 37, '1600 Pentagon Rd',         'Arlington',        'Virginia',       '22202'),
-- Mayweather
(46, 38, '400 Inner Harbor Dr',      'Baltimore',        'Maryland',       '21202'),
-- Burnham (2 addresses)
(47, 39, '200 Euclid Ave',           'Cleveland',        'Ohio',           '44114'),
(48, 39, '75 Discovery Way',         'San Francisco',    'California',     '94130'),
-- Saru
(49, 40, '150 Beale St',             'Memphis',          'Tennessee',      '38103'),
-- Tilly
(50, 41, '425 Wisconsin Ave',        'Milwaukee',        'Wisconsin',      '53202'),
-- Stamets
(51, 42, '300 Grand Blvd',           'Kansas City',      'Missouri',       '64108'),
-- Culber
(52, 43, '195 River Walk',           'San Antonio',      'Texas',          '78205'),
-- Pike (2 addresses)
(53, 44, '50 Desert Springs Rd',     'Mojave',           'California',     '93501'),
(54, 44, '2 Fleet Admiral Ln',       'San Francisco',    'California',     '94131'),
-- Chin-Riley
(55, 45, '800 Monument Cir',         'Indianapolis',     'Indiana',        '46204'),
-- Mariner (2 addresses)
(56, 46, '100 Jack London Sq',       'Oakland',          'California',     '94607'),
(57, 46, '30 Cerritos Way',          'San Francisco',    'California',     '94132'),
-- Boimler
(58, 47, '250 McHenry Ave',          'Modesto',          'California',     '95354'),
-- Freeman
(59, 48, '175 Broadway',             'Oakland',          'California',     '94612'),
-- Ransom
(60, 49, '500 Trade St',             'Charlotte',        'North Carolina', '28202'),
-- Rutherford
(61, 50, '300 Fayetteville St',      'Raleigh',          'North Carolina', '27601');

SET IDENTITY_INSERT dbo.[Address] OFF;

END -- IF NOT EXISTS

-- Dynamic data masking: SSN shows as XXX-XX-1234 for non-privileged users
IF NOT EXISTS (
    SELECT 1 FROM sys.masked_columns
    WHERE object_id = OBJECT_ID('dbo.Contact') AND name = 'SSN'
)
    ALTER TABLE dbo.Contact ALTER COLUMN [SSN] ADD MASKED WITH (FUNCTION = 'partial(0,"XXX-XX-",4)');
