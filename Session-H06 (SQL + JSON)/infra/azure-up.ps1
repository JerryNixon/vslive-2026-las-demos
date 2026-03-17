#!/usr/bin/env pwsh
<#
    azure-up.ps1 – Deploy Session H06 to Azure
    ────────────────────────────────────────────
    Usage:  .\infra\azure-up.ps1 [-ResourceGroup rg-h06-demo] [-Location westus2]

    Deploys:
        1. Azure SQL Server (free tier CrmDb + Basic CompanyDb)
        2. DAB container on Azure Container Apps
        3. Schema + seed data via sqlpackage
        4. crmUser SQL login for DAB
#>

param(
    [string]$ResourceGroup  = "rg-h06-demo",
    [string]$Location       = "westus2",
    [string]$SqlAdminLogin  = "sqladmin",
    [string]$SqlAdminPassword = "Sql@dmin2026!"
)

$ErrorActionPreference = 'Stop'
$infraDir   = $PSScriptRoot
$sessionDir = Split-Path $infraDir -Parent

function Invoke-Sql($Server, $Database, $User, $Password, $Query) {
    $cs = "Server=$Server;Database=$Database;User Id=$User;Password=$Password;TrustServerCertificate=true;Encrypt=true;Connection Timeout=60;"
    $c = New-Object System.Data.SqlClient.SqlConnection($cs)
    $c.Open()
    $cmd = $c.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = 120
    $cmd.ExecuteNonQuery() | Out-Null
    $c.Close()
}

# Step 1: Create resource group
Write-Host "`n[1/7] Creating resource group..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none

# Step 2: Deploy Bicep infrastructure
Write-Host "[2/7] Deploying infrastructure (SQL + ACR + ACA)..." -ForegroundColor Cyan
$outputs = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$infraDir/main.bicep" `
    --parameters location=$Location sqlAdminLogin=$SqlAdminLogin sqlAdminPassword=$SqlAdminPassword `
    --query "properties.outputs" -o json 2>$null | ConvertFrom-Json

$sqlServerFqdn  = $outputs.SQL_SERVER_FQDN.value
$sqlServerName  = $outputs.SQL_SERVER_NAME.value
$acrName        = $outputs.ACR_NAME.value
$acrLoginServer = $outputs.ACR_LOGIN_SERVER.value
$dabEndpointUrl = $outputs.DAB_ENDPOINT_URL.value

Write-Host "  SQL Server: $sqlServerFqdn" -ForegroundColor Gray
Write-Host "  ACR:        $acrLoginServer" -ForegroundColor Gray
Write-Host "  DAB URL:    $dabEndpointUrl" -ForegroundColor Gray

# Step 3: Open firewall for demo + deploy CrmDb
Write-Host "[3/7] Opening firewall + deploying CrmDb..." -ForegroundColor Cyan
az sql server firewall-rule create --resource-group $ResourceGroup --server $sqlServerName `
    --name "AllowAll" --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255 --output none

dotnet build "$sessionDir/database/CrmDb/CrmDb.sqlproj" --nologo -v quiet
$crmConn = "Server=$sqlServerFqdn;Database=CrmDb;User Id=$SqlAdminLogin;Password=$SqlAdminPassword;TrustServerCertificate=true;Encrypt=true;"
sqlpackage /Action:Publish /SourceFile:"$sessionDir/database/CrmDb/bin/Debug/CrmDb.dacpac" /TargetConnectionString:"$crmConn" /p:BlockOnPossibleDataLoss=false /Quiet
Write-Host "  CrmDb: 50 contacts, 61 addresses" -ForegroundColor Green

# Step 4: Create crmUser
Write-Host "[4/7] Creating crmUser..." -ForegroundColor Cyan
Invoke-Sql $sqlServerFqdn 'master' $SqlAdminLogin $SqlAdminPassword `
    "IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = 'crmUser') CREATE LOGIN crmUser WITH PASSWORD = 'P@ssw0rd!';"
Invoke-Sql $sqlServerFqdn 'CrmDb' $SqlAdminLogin $SqlAdminPassword `
    "IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'crmUser') BEGIN CREATE USER crmUser FOR LOGIN crmUser; ALTER ROLE db_datareader ADD MEMBER crmUser; ALTER ROLE db_datawriter ADD MEMBER crmUser; END"
Invoke-Sql $sqlServerFqdn 'CrmDb' $SqlAdminLogin $SqlAdminPassword `
    "DENY UPDATE ON dbo.Contact(SSN) TO crmUser;"
Write-Host "  crmUser: db_datareader + db_datawriter on CrmDb (DENY UPDATE on SSN)" -ForegroundColor Green

# Step 5: Deploy CompanyDb
Write-Host "[5/7] Deploying CompanyDb..." -ForegroundColor Cyan
dotnet build "$sessionDir/database/CompanyDb/CompanyDb.sqlproj" --nologo -v quiet
$companyConn = "Server=$sqlServerFqdn;Database=CompanyDb;User Id=$SqlAdminLogin;Password=$SqlAdminPassword;TrustServerCertificate=true;Encrypt=true;"
sqlpackage /Action:Publish /SourceFile:"$sessionDir/database/CompanyDb/bin/Debug/CompanyDb.dacpac" /TargetConnectionString:"$companyConn" /p:BlockOnPossibleDataLoss=false /Quiet
Write-Host "  CompanyDb: tables + view + import proc" -ForegroundColor Green

# Step 6: Build and deploy DAB container
Write-Host "[6/7] Building DAB container + deploying to ACA..." -ForegroundColor Cyan
az acr build --registry $acrName --image dab-api:latest "$sessionDir/data-api" --no-logs

$acrPassword = (az acr credential show --name $acrName --query "passwords[0].value" -o tsv 2>$null)
az containerapp registry set --name ca-dab-api --resource-group $ResourceGroup `
    --server $acrLoginServer --username $acrName --password $acrPassword --output none
az containerapp update --name ca-dab-api --resource-group $ResourceGroup `
    --image "$acrLoginServer/dab-api:latest" --output none
Write-Host "  DAB deployed to ACA" -ForegroundColor Green

# Step 7: Verify
Write-Host "[7/7] Verifying DAB API..." -ForegroundColor Cyan
$healthy = $false
for ($i = 1; $i -le 15; $i++) {
    try {
        $resp = Invoke-RestMethod -Uri "$dabEndpointUrl/api/Contact" -TimeoutSec 10
        Write-Host "  REST /api/Contact: $($resp.value.Count) contacts" -ForegroundColor Green
        $healthy = $true
        break
    } catch {
        Write-Host "  Attempt $i/15 - waiting..." -ForegroundColor Gray
        Start-Sleep -Seconds 15
    }
}

if (-not $healthy) { Write-Host "  WARNING: DAB not responding" -ForegroundColor Red }

# Summary
Write-Host "`n════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Deployment Complete!"                      -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "  SQL Server:  $sqlServerFqdn"              -ForegroundColor Gray
Write-Host "  DAB API:     $dabEndpointUrl/health"             -ForegroundColor Gray
Write-Host "  REST:        $dabEndpointUrl/swagger"         -ForegroundColor Gray
Write-Host "  GraphQL:     $dabEndpointUrl/graphql"     -ForegroundColor Gray
Write-Host ""
Write-Host "  Import CRM data into CompanyDb:" -ForegroundColor White
Write-Host "    EXEC dbo.Crm_ImportAll @DabEndpointUrl = '$dabEndpointUrl'" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Tear down:" -ForegroundColor White
Write-Host "    .\infra\azure-down.ps1" -ForegroundColor Yellow
Write-Host ""
