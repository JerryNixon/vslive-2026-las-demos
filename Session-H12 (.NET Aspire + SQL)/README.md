# H12: .NET Aspire & SQL Server — A Developer's Dream Comes True

**Date:** March 19, 2026 | 1:15 PM – 2:30 PM  
**Level:** Intermediate to Advanced  
**Speaker:** Jerry Nixon — SQL Server Product Manager, Microsoft

---

## Overview

This session is designed for .NET developers ready to get started with .NET Aspire using SQL Server — in Azure, in Fabric, on-premises, and wherever the SQL Server engine is available. With a focus on common questions and integrations like EF Core and Data API Builder, this session provides foundational knowledge and practical insights.

## What You'll Learn

- How to start from scratch with Aspire and a SQL Server database you already have
- The basics of .NET Aspire with SQL Server and Azure SQL Database
- How to use Data API Builder and EF Core with Aspire

## Prerequisites

- [.NET 10+ SDK](https://dot.net)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)

## Running the Demo

```powershell
cd aspire-apphost
dotnet run
```

Then open the **Aspire Dashboard** at the URL shown in the terminal (typically `http://localhost:15888`).

## Project Structure

```
Session-H12/
├── aspire-apphost/          # Aspire AppHost orchestration
│   ├── AppHost.csproj
│   └── Program.cs
├── data-api/                # Data API Builder configuration
│   └── dab-config.json
├── database/
│   ├── CatalogDb/           # Product catalog schema
│   │   ├── Tables/
│   │   │   ├── Categories.sql
│   │   │   └── Products.sql
│   │   ├── Scripts/
│   │   │   └── PostDeployment.sql
│   │   └── CatalogDb.sqlproj
│   └── InventoryDb/         # Inventory schema
│       ├── Tables/
│       │   ├── Warehouses.sql
│       │   └── Inventory.sql
│       ├── Scripts/
│       │   └── PostDeployment.sql
│       └── InventoryDb.sqlproj
└── .env                     # Secrets (gitignored)
```

## Databases

### CatalogDb — Product Catalog

| Table | Purpose |
|-------|---------|
| **Categories** | Ship types (Federation, Klingon, Romulan, Borg, Stations) |
| **Products** | Star Trek ship models with scale, price, and category |

### InventoryDb — Warehouse Inventory

| Table | Purpose |
|-------|---------|
| **Warehouses** | Storage locations (Utopia Planitia, SF Fleet Yards, Starbase 74) |
| **Inventory** | Stock levels per product per warehouse |

## Services

| Service | Description |
|---------|-------------|
| **SQL Server** | Single instance hosting both CatalogDb and InventoryDb |
| **Data API Builder** | REST, GraphQL, and MCP endpoints over CatalogDb |
| **SQL Commander (Catalog)** | Browser-based SQL tool for CatalogDb |
| **SQL Commander (Inventory)** | Browser-based SQL tool for InventoryDb |
| **MCP Inspector** | Debug and test MCP endpoints |

All services are visible in the Aspire Dashboard with logs, metrics, and traces.
