-- CompanyDb Post-Deployment Script
-- Seed data: DocumentStore sample documents

INSERT INTO dbo.DocumentStore (DocumentType, Data) VALUES
('employee',  '{"name": "James Kirk",       "email": "jkirk@starfleet.org",     "department": "Command",     "status": "active"}'),
('employee',  '{"name": "Spock Grayson",    "email": "spock@starfleet.org",     "department": "Science",     "status": "active"}'),
('employee',  '{"name": "Leonard McCoy",    "email": "lmccoy@starfleet.org",    "department": "Medical",     "status": "active"}'),
('employee',  '{"name": "Montgomery Scott", "email": "mscott@starfleet.org",    "department": "Engineering", "status": "active"}'),
('project',   '{"name": "Warp Core Refit",  "email": "warpcore@starfleet.org",  "budget": 500000, "status": "pending"}'),
('project',   '{"name": "Shield Upgrade",   "email": "shields@starfleet.org",   "budget": 250000, "status": "active"}');
