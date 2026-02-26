---
name: data-api-builder-demo
description: Build and maintain Data API Builder (DAB) quickstart demos with consistent folder structure, naming, and validation. Use when creating a new quickstart, renaming folders, validating demo structure, or preparing a presentation.
---

# Data API Builder — Demo Operations

This skill captures lessons learned from building the DAB quickstart series. Follow these rules when creating, modifying, or validating any quickstart project.

---

## Quickstart Folder Structure

Every quickstart follows this canonical layout:

```
quickstart<N>/
  ├── quickstart<N>.sln         # Solution file
  ├── azure.yaml                # azd entry point
  ├── database.sql              # Legacy flat schema (keep for reference)
  ├── README.md                 # Quickstart documentation
  ├── .gitignore                # Must exclude .env, **\bin, **\obj
  ├── .config/
  │   └── dotnet-tools.json     # Tool manifest (dab, sqlpackage)
  ├── aspire-apphost/           # .NET Aspire orchestration
  │   ├── Aspire.AppHost.csproj
  │   └── Program.cs
  ├── data-api/                 # DAB configuration + Dockerfile
  │   ├── dab-config.json
  │   └── Dockerfile
  ├── database/                 # SQL Database Project
  │   ├── database.sqlproj
  │   ├── database.publish.xml
  │   ├── Tables/*.sql
  │   └── Scripts/PostDeployment.sql
  ├── mcp-inspector/            # MCP Inspector containerization (for Azure)
  │   ├── Dockerfile
  │   ├── entrypoint.sh
  │   └── nginx.conf
  ├── web-app/                  # Frontend (nginx-served static files)
  │   ├── index.html
  │   ├── app.js
  │   ├── config.js
  │   ├── dab.js
  │   ├── styles.css
  │   └── Dockerfile
  └── azure-infra/              # Azure deployment (Bicep + scripts)
    ├── azure-up.ps1
    ├── azure-down.ps1
      ├── main.bicep
      ├── resources.bicep
      └── post-provision.ps1

# Repo root runtime utilities
reset.ps1                        # Resets quickstarts to demo-ready defaults
.github/mcp.json                 # Workspace MCP registry for Azure quickstarts (created on demand)
```

---

## Folder Naming Conventions

| Folder | Name | Rationale |
|--------|------|-----------|
| Aspire orchestration | `aspire-apphost` | Lowercase, hyphenated — matches skill naming |
| DAB config | `data-api` | Describes what it is, not the tool |
| Database project | `database` | Standard SQL project location |
| MCP Inspector | `mcp-inspector` | Full name, not abbreviated |
| Web frontend | `web-app` | Distinguishes from web API |
| Azure infrastructure | `azure-infra` | Clarifies it's infrastructure, not app code |

**Rules:**
- All folder names are **lowercase with hyphens**
- No dots in folder names (use `aspire-apphost`, not `Aspire.AppHost`)
- The `.csproj` file name inside can differ from the folder name

---

## Renaming Folders — Checklist

When renaming any folder, **always** update all references. Files that commonly contain folder paths:

| File | What to check |
|------|---------------|
| `*.sln` | Project path in `Project(...)` line |
| `azure.yaml` | `infra.path` and `hooks.*.run` paths |
| `aspire-apphost/Program.cs` | `Path.Combine(root, ...)` references |
| `azure-infra/post-provision.ps1` | `Copy-Item`, file path strings |
| `aspire-apphost/*.csproj` | `<ProjectReference>` paths |
| `README.md` | Folder references (usually none — keep READMEs path-free) |

**After every rename:**

1. **Search for the old name** across the quickstart — use regex `\bold-name[/\\]` and `"old-name"`
2. **Update all references** found
3. **Clean and rebuild** — `Remove-Item -Recurse obj, bin; dotnet build`
4. **Verify build succeeds** with 0 errors
5. **Review the README** — confirm it doesn't reference folder paths directly

> **Tip:** `obj/` and `bin/` contain cached paths. Always delete them after renames and rebuild.

---

## README Standards

Each quickstart README follows this structure:

1. **Title** — `# Quickstart N: <Auth Topic>`
2. **Intro** — 2-3 sentences explaining the auth pattern
3. **What You'll Learn** — Bullet list (3-4 items)
4. **Auth Matrix** — Table showing auth at each hop
5. **Architecture** — Mermaid flowchart showing services and auth flows
6. **Considerations** — Callout about the auth pattern's tradeoffs
7. **Connection String Example** — Formatted connection string for the pattern
8. **Prerequisites** — Links to required tools
9. **Run Locally** — Exact commands (`dotnet tool restore`, `aspire run`)
10. **Deploy to Azure** — Exact commands (`pwsh ./azure-infra/azure-up.ps1`)
11. **Database Schema** — Mermaid ERD matching the SQL Database Project
12. **Next Steps** — Links to other quickstarts

**README rules:**
- **Never reference folder paths** — keep READMEs resilient to renames
- **Mermaid ERD types must be simple** — `nvarchar` not `nvarchar(200)`
- **Architecture diagrams use service names** — no ports, no versions
- **Auth matrix must match the actual implementation** — verify against `dab-config.json` and Bicep
- **Keep it under 120 lines** — concise is better

## Azure Naming and Tagging Standards

For Azure deployments, these rules are mandatory:

- **Token format:** use UTC timestamp `yyyyMMddHHmm` (example: `202602230559`) for readable resource suffixes.
- **Owner tag required:** every Azure resource that supports tags must include `owner`.
- **Owner value source:** derive from signed-in user alias (left side of `@` from `az account show --query user.name -o tsv`).
    - Example: `jnixon@domain.com` → `owner: jnixon`
- **Tag propagation:** define `owner` once in `azure-infra/main.bicep` `tags` and pass it to all resources/modules.
- **Script entrypoints:** use `azure-infra/azure-up.ps1` and `azure-infra/azure-down.ps1`.
- **No legacy wrappers:** do not create or reference `aspire-up.ps1` / `aspire-down.ps1` in `azure-infra`.

## MCP Registry Standards

- Azure deployments register MCP servers in **repo-root** `.github/mcp.json` (not per-quickstart files).
- Server names must be deterministic per quickstart:
    - `azure-sql-mcp-qs1`, `azure-sql-mcp-qs2`, `azure-sql-mcp-qs3`, `azure-sql-mcp-qs4`, `azure-sql-mcp-qs5`
- Server URL format: `https://<dab-fqdn>/mcp`
- `azure-up.ps1` flow: create/update the quickstart server entry without altering other user entries.
- `azure-down.ps1` flow: remove only that quickstart server entry, preserving all others.

## Reset Workflow Standards

- Maintain a repo-root `reset.ps1` that returns quickstarts to demo-ready state.
- Reset should remove run-specific artifacts (such as `.azure`, `.azure-env`, deploy-temp folders, temp JSON files).
- Reset should restore `web-app/config.js` placeholders per quickstart.
- Reset should remove `azure-sql-mcp-qs*` entries from `.github/mcp.json` without removing user-defined servers.

---

## Consistency Between Quickstarts

The quickstarts form a progressive series. Each one adds complexity:

| QS | Auth Pattern | Delta from Previous |
|----|-------------|-------------------|
| 1 | SQL Auth everywhere | Baseline |
| 2 | Managed Identity (API→SQL) | Replaces SQL Auth on the DB hop |
| 3 | Entra ID infrastructure | Adds app registrations, no user login yet |
| 4 | User login + DAB policy | Adds frontend auth, per-user filtering |
| 5 | Row-Level Security | Moves filtering into SQL |

**Cross-quickstart rules:**
- Folder structure must be **identical** across all quickstarts
- Folder names must match (if you rename in one, rename in all)
- README format must be consistent
- `database/` SQL Database Project is the single source of truth for schema
- Each quickstart is **self-contained** — can be deployed independently

---

## Validation Checklist (Before Demo)

Run through this before any presentation or PR:

### Build Validation

```powershell
cd quickstart<N>
dotnet tool restore
dotnet build aspire-apphost/Aspire.AppHost.csproj
```

Must complete with 0 errors, 0 warnings.

### Structure Validation

```powershell
# Verify all expected folders exist
$expected = @('aspire-apphost', 'data-api', 'database', 'mcp-inspector', 'web-app', 'azure-infra')
$expected | ForEach-Object { if (!(Test-Path $_)) { Write-Warning "Missing: $_" } }
```

### File Validation

```powershell
# Verify critical files exist
$files = @(
    'azure.yaml',
    'quickstart<N>.sln',
    'README.md',
    '.gitignore',
    'data-api/dab-config.json',
    'data-api/Dockerfile',
    'database/database.sqlproj',
    'aspire-apphost/Aspire.AppHost.csproj',
    'aspire-apphost/Program.cs',
    'azure-infra/main.bicep',
    'azure-infra/resources.bicep',
    'azure-infra/post-provision.ps1'
)
$files | ForEach-Object { if (!(Test-Path $_)) { Write-Warning "Missing: $_" } }
```

### Azure Tag Validation

```powershell
# Verify owner tag wiring in templates
Get-ChildItem quickstart*\azure-infra\main.bicep | Select-String -Pattern "ownerAlias|owner:|var tags" | Out-Host
```

```powershell
# Verify token + owner env setup in deployment scripts
Get-ChildItem quickstart*\azure-infra\azure-up.ps1, quickstart*\azure-infra\entra-setup.ps1 -ErrorAction SilentlyContinue |
    Select-String -Pattern "AZURE_RESOURCE_TOKEN|yyyyMMddHHmm|AZURE_OWNER_ALIAS|user.name" | Out-Host
```

### MCP Registry Validation

```powershell
# Ensure Azure quickstart MCP entries are managed in repo-root registry
if (Test-Path .github/mcp.json) {
    Get-Content .github/mcp.json -Raw | Select-String -Pattern 'azure-sql-mcp-qs[1-5]|"url"\s*:\s*"https://.*/mcp"' -AllMatches | Out-Host
}
```

```powershell
# Ensure no legacy azure-infra aspire-up/down scripts remain
Get-ChildItem quickstart*\azure-infra\aspire-*.ps1 -ErrorAction SilentlyContinue | Out-Host
```

### Cross-Reference Validation

```powershell
# Check for stale folder references
$staleNames = @('Aspire.AppHost', '/api/', '/web/', '/azure/', '/inspector/')
$staleNames | ForEach-Object {
    $hits = Get-ChildItem -Recurse -Include *.cs,*.yaml,*.sln,*.ps1,*.csproj | Select-String -Pattern $_ -SimpleMatch
    if ($hits) { Write-Warning "Stale reference to '$_' found:"; $hits | ForEach-Object { Write-Warning "  $_" } }
}
```

### .gitignore Validation

Before committing, verify `.gitignore` is correct and no build artifacts will leak into the repo.

**Required ignore patterns:**
```
.env
.azure-env
.azure/
dab-config.*.json
**/bin
**/obj
node_modules/
web-deploy-temp/
api-deploy-temp/
web-deploy.zip
```

> **CRITICAL:** Use `**/bin` and `**/obj` (not `bin/` and `obj/`) — the root-only pattern misses nested project folders like `aspire-apphost/bin/`.

**Count untracked files before committing:**
```powershell
# Show how many files git will add
$untracked = git ls-files --others --exclude-standard
Write-Host "Untracked files: $($untracked.Count)"
$untracked
```

Review the list — every file should be legitimate source. If you see `bin/`, `obj/`, `.env`, or deploy temp folders, fix `.gitignore` before committing. A typical quickstart has ~20-25 source files; significantly more suggests a missing ignore pattern.

---

## Common Pitfalls

### Folder rename breaks build
- **Cause:** `obj/` and `bin/` cache absolute paths from before the rename
- **Fix:** Delete `obj/` and `bin/`, rebuild

### `azure-up.ps1` can't find Bicep
- **Cause:** `azure.yaml` still points to old `infra.path`
- **Fix:** Update `path` and `run` fields in `azure.yaml`

### Solution file won't load project
- **Cause:** `.sln` has old folder path in `Project(...)` line
- **Fix:** Update the path — keep the project GUID unchanged

### Post-provision script fails
- **Cause:** `Copy-Item` or file paths reference old folder names
- **Fix:** Search `post-provision.ps1` for all folder references

### Program.cs can't find dab-config.json
- **Cause:** `Path.Combine(root, "api", ...)` still uses old path
- **Fix:** Update all `Path.Combine` calls in `Program.cs`

### Web app shows stale content
- **Cause:** `config.js` wasn't regenerated after Azure deployment changes
- **Fix:** Re-run post-provision or manually update `config.js`

### Missing required owner tag
- **Cause:** `AZURE_OWNER_ALIAS` not set or `owner` not included in `main.bicep` tags
- **Fix:** set `AZURE_OWNER_ALIAS` in `azure-up` flow and include `owner: ownerAlias` in `tags`

### MCP servers overwritten or missing
- **Cause:** `azure-up` rewrote `.github/mcp.json` incorrectly or `azure-down` removed unrelated entries
- **Fix:** always upsert/remove only the quickstart key (`azure-sql-mcp-qsN`) and preserve all other `servers` entries

### Legacy script names referenced
- **Cause:** README/scripts still reference `aspire-up.ps1`/`aspire-down.ps1`
- **Fix:** standardize on `azure-up.ps1` and `azure-down.ps1` for all Azure quickstart operations

---

## Peer Skills Reference

| Skill | Use For |
|-------|---------|
| `aspire-data-api-builder` | Local Aspire orchestration |
| `docker-data-api-builder` | Local Docker Compose orchestration |
| `azure-data-api-builder` | Azure deployment (Bicep, azd, ACR) |
| `data-api-builder-config` | DAB config file reference |
| `data-api-builder-cli` | DAB CLI commands |
| `data-api-builder-mcp` | MCP endpoint setup |
| `aspire-mcp-inspector` | Local MCP Inspector in Aspire |
| `azure-mcp-inspector` | Azure MCP Inspector deployment |
| `aspire-sql-commander` | Local SQL Commander in Aspire |
| `azure-sql-commander` | Azure SQL Commander deployment |
| `aspire-sql-projects` | SQL Database Projects in Aspire |
| `creating-agent-skills` | How to create new skills |
