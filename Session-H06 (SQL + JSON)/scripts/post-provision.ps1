#!/usr/bin/env pwsh
<#
    Post-Provision Script
    ---------------------
    Runs after 'azd provision' creates the Azure infrastructure.
    
    1. Adds client IP to SQL firewall
    2. Builds and deploys CrmDb schema + seed data
    3. Creates crmUser (SQL auth for DAB)
    4. Builds and deploys CompanyDb schema + stored proc
    5. Builds and pushes DAB container image to ACR
    6. Updates the ACA container app with the real DAB image
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ──────── Read azd environment values ────────
$sqlServerFqdn   = (azd env get-value SQL_SERVER_FQDN)
$sqlServerName   = (azd env get-value SQL_SERVER_NAME)
$acrName         = (azd env get-value ACR_NAME)
$acrLoginServer  = (azd env get-value ACR_LOGIN_SERVER)
$dabEndpointUrl  = (azd env get-value DAB_ENDPOINT_URL)
$rg              = (azd env get-value AZURE_RESOURCE_GROUP)
$sqlAdminLogin   = (azd env get-value SQL_ADMIN_LOGIN)
$sqlAdminPassword = (azd env get-value SQL_ADMIN_PASSWORD)

$sessionDir = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Post-Provision Deployment"              -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan

# ──────── Helper: Run SQL against Azure SQL ────────
function Invoke-Sql {
    param(
        [string]$Server,
        [string]$Database,
        [string]$User,
        [string]$Password,
        [string]$Query
    )
    $connString = "Server=$Server;Database=$Database;User Id=$User;Password=$Password;TrustServerCertificate=true;Encrypt=true;Connection Timeout=60;"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = 120
    $result = $cmd.ExecuteNonQuery()
    $conn.Close()
    return $result
}

# ══════════════════════════════════════════════════
#  Step 1 – Add client IP to SQL Server firewall
# ══════════════════════════════════════════════════

Write-Host "`n→ Step 1: Adding client IP to SQL firewall..." -ForegroundColor Yellow
$myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10)
az sql server firewall-rule create `
    --resource-group $rg `
    --server $sqlServerName `
    --name "ClientIP-$(Get-Date -Format 'yyyyMMddHHmm')" `
    --start-ip-address $myIp `
    --end-ip-address $myIp `
    --output none
Write-Host "  Added firewall rule for $myIp" -ForegroundColor Gray

# ══════════════════════════════════════════════════
#  Step 2 – Build and deploy CrmDb
# ══════════════════════════════════════════════════

Write-Host "`n→ Step 2: Building CrmDb..." -ForegroundColor Yellow
dotnet build "$sessionDir/database/CrmDb/CrmDb.sqlproj" --nologo -v quiet
if ($LASTEXITCODE -ne 0) { throw "CrmDb build failed" }

Write-Host "  Publishing CrmDb schema + seed data..." -ForegroundColor Gray
$crmConn = "Server=$sqlServerFqdn;Database=CrmDb;User Id=$sqlAdminLogin;Password=$sqlAdminPassword;TrustServerCertificate=true;Encrypt=true;"
sqlpackage /Action:Publish `
    /SourceFile:"$sessionDir/database/CrmDb/bin/Debug/CrmDb.dacpac" `
    /TargetConnectionString:"$crmConn" `
    /p:BlockOnPossibleDataLoss=false `
    /Quiet
if ($LASTEXITCODE -ne 0) { throw "CrmDb publish failed" }
Write-Host "  CrmDb deployed (50 contacts, 61 addresses)" -ForegroundColor Green

# ══════════════════════════════════════════════════
#  Step 3 – Create crmUser (SQL auth for DAB)
# ══════════════════════════════════════════════════

Write-Host "`n→ Step 3: Creating crmUser login..." -ForegroundColor Yellow

# Server-level login (master)
Invoke-Sql -Server $sqlServerFqdn -Database 'master' `
    -User $sqlAdminLogin -Password $sqlAdminPassword `
    -Query @"
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = 'crmUser')
    CREATE LOGIN crmUser WITH PASSWORD = 'P@ssw0rd!';
"@

# Database-level user + read permission (CrmDb)
Invoke-Sql -Server $sqlServerFqdn -Database 'CrmDb' `
    -User $sqlAdminLogin -Password $sqlAdminPassword `
    -Query @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'crmUser')
BEGIN
    CREATE USER crmUser FOR LOGIN crmUser;
    ALTER ROLE db_datareader ADD MEMBER crmUser;
END
"@
Write-Host "  crmUser created with db_datareader on CrmDb" -ForegroundColor Green

# ══════════════════════════════════════════════════
#  Step 4 – Build and deploy CompanyDb
# ══════════════════════════════════════════════════

Write-Host "`n→ Step 4: Building CompanyDb..." -ForegroundColor Yellow
dotnet build "$sessionDir/database/CompanyDb/CompanyDb.sqlproj" --nologo -v quiet
if ($LASTEXITCODE -ne 0) { throw "CompanyDb build failed" }

Write-Host "  Publishing CompanyDb schema + stored proc..." -ForegroundColor Gray
$companyConn = "Server=$sqlServerFqdn;Database=CompanyDb;User Id=$sqlAdminLogin;Password=$sqlAdminPassword;TrustServerCertificate=true;Encrypt=true;"
sqlpackage /Action:Publish `
    /SourceFile:"$sessionDir/database/CompanyDb/bin/Debug/CompanyDb.dacpac" `
    /TargetConnectionString:"$companyConn" `
    /p:BlockOnPossibleDataLoss=false `
    /Quiet
if ($LASTEXITCODE -ne 0) { throw "CompanyDb publish failed" }
Write-Host "  CompanyDb deployed (tables + view + import proc)" -ForegroundColor Green

# ══════════════════════════════════════════════════
#  Step 5 – Build and push DAB container image
# ══════════════════════════════════════════════════

Write-Host "`n→ Step 5: Building DAB container image in ACR..." -ForegroundColor Yellow
az acr build `
    --registry $acrName `
    --image dab-api:latest `
    "$sessionDir/data-api" `
    --no-logs
if ($LASTEXITCODE -ne 0) { throw "ACR build failed" }
Write-Host "  Image pushed: $acrLoginServer/dab-api:latest" -ForegroundColor Green

# ══════════════════════════════════════════════════
#  Step 6 – Update Container App with real DAB image
# ══════════════════════════════════════════════════

Write-Host "`n→ Step 6: Deploying DAB to Container App..." -ForegroundColor Yellow
$acrPassword = (az acr credential show --name $acrName --query "passwords[0].value" -o tsv)

az containerapp update `
    --name ca-dab-api `
    --resource-group $rg `
    --image "$acrLoginServer/dab-api:latest" `
    --registry-server $acrLoginServer `
    --registry-username $acrName `
    --registry-password $acrPassword `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Container App update failed" }
Write-Host "  DAB deployed to ACA" -ForegroundColor Green

# ══════════════════════════════════════════════════
#  Step 7 – Wait for DAB to be healthy
# ══════════════════════════════════════════════════

Write-Host "`n→ Step 7: Waiting for DAB health check..." -ForegroundColor Yellow
$healthUrl = "$dabEndpointUrl/health"
$maxRetries = 20
$healthy = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 10
        if ($resp.StatusCode -eq 200) {
            $healthy = $true
            break
        }
    } catch {
        Write-Host "  Attempt $i/$maxRetries - waiting..." -ForegroundColor Gray
        Start-Sleep -Seconds 15
    }
}

if ($healthy) {
    Write-Host "  DAB is healthy at $dabEndpointUrl" -ForegroundColor Green
} else {
    Write-Host "  WARNING: DAB did not respond to health check after $maxRetries attempts" -ForegroundColor Red
    Write-Host "  Check the container logs in Azure Portal" -ForegroundColor Red
}

# ══════════════════════════════════════════════════
#  Done
# ══════════════════════════════════════════════════

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Deployment Complete"                    -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "  SQL Server:  $sqlServerFqdn"           -ForegroundColor Gray
Write-Host "  DAB API:     $dabEndpointUrl"          -ForegroundColor Gray
Write-Host "  DAB Health:  $dabEndpointUrl/health"   -ForegroundColor Gray
Write-Host "  REST API:    $dabEndpointUrl/api"      -ForegroundColor Gray
Write-Host "  GraphQL:     $dabEndpointUrl/graphql"  -ForegroundColor Gray
Write-Host ""
Write-Host "  To import CRM data into CompanyDb, run:" -ForegroundColor Gray
Write-Host "    EXEC dbo.Crm_ImportAll @DabEndpointUrl = '$dabEndpointUrl'" -ForegroundColor White
Write-Host ""
