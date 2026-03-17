#!/usr/bin/env pwsh
<#
    azure-up.ps1 – Deploy Session W05 (AI + Data) to Azure
    ───────────────────────────────────────────────────────
    Deploys:
      1. Azure SQL (GP Serverless) + AiDemoDb schema + seed data
      2. External model, ReviewVector table, views, procs, trigger
      3. Data API Builder (DAB) on Azure Container Apps with MCP enabled
      4. Azure Function (EmbedOnChange) with SQL trigger binding
#>
param(
    [string]$ResourceGroup    = "rg-w05-demo",
    [string]$Location         = "centralus",
    [string]$SqlAdminLogin    = "sqladmin",
    [string]$SqlAdminPassword = $env:SQL_ADMIN_PASSWORD,
    [string]$OpenAIKey        = $env:OPENAI_KEY,
    [string]$OpenAIEndpoint   = $env:OPENAI_ENDPOINT
)

$ErrorActionPreference = 'Stop'
$infraDir   = $PSScriptRoot
$sessionDir = Split-Path $infraDir -Parent
$dbDir      = "$sessionDir\database\AiDemoDb"
$funcDir    = "$sessionDir\function"
$dabDir     = "$sessionDir\data-api"

# Load .env if params were not provided
$envFile = "$sessionDir\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+)$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
}
if (-not $SqlAdminPassword) { $SqlAdminPassword = $env:SQL_ADMIN_PASSWORD }
if (-not $OpenAIKey)        { $OpenAIKey = $env:OPENAI_KEY }
if (-not $OpenAIEndpoint)   { $OpenAIEndpoint = $env:OPENAI_ENDPOINT }
if (-not $SqlAdminPassword -or -not $OpenAIKey -or -not $OpenAIEndpoint) {
    Write-Error "Missing secrets. Set SQL_ADMIN_PASSWORD, OPENAI_KEY, and OPENAI_ENDPOINT in .env or pass as parameters."
    exit 1
}

function Invoke-Sql($Server, $Db, $Query) {
    $cs = "Server=$Server;Database=$Db;User Id=$SqlAdminLogin;Password=$SqlAdminPassword;TrustServerCertificate=true;Encrypt=true;Connection Timeout=60;"
    $c = New-Object System.Data.SqlClient.SqlConnection($cs)
    $c.Open()
    $cmd = $c.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = 300
    try { $cmd.ExecuteNonQuery() | Out-Null } finally { $c.Close() }
}

function Invoke-SqlFile($Server, $Db, $File) {
    $raw = Get-Content $File -Raw
    $raw = $raw.Replace('$(OPENAI_KEY)', $OpenAIKey)
    $raw = $raw.Replace('$(OPENAI_ENDPOINT)', $OpenAIEndpoint)
    foreach ($batch in ($raw -split '(?m)^\s*GO\s*$')) {
        $batch = $batch.Trim()
        if ($batch.Length -gt 0) { Invoke-Sql $Server $Db $batch }
    }
}

# ── 1. Resource group ──────────────────────────────────
Write-Host "`n[1/9] Creating resource group..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none

# ── 2. Bicep deployment ────────────────────────────────
Write-Host "[2/9] Deploying infrastructure (SQL + ACR + ACA)..." -ForegroundColor Cyan
$deployJson = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$infraDir/main.bicep" `
    --parameters location=$Location sqlAdminLogin=$SqlAdminLogin sqlAdminPassword=$SqlAdminPassword `
    --query "properties.outputs" -o json
$outputs = $deployJson | ConvertFrom-Json

$sqlFqdn   = $outputs.sQL_SERVER_FQDN.value
$sqlName   = $outputs.sQL_SERVER_NAME.value
$dbName    = $outputs.dB_NAME.value
$funcApp   = $outputs.fUNC_APP_NAME.value
$storageName = $outputs.sTORAGE_NAME.value
$acrName   = $outputs.aCR_NAME.value
$acrLogin  = $outputs.aCR_LOGIN_SERVER.value
$dabUrl    = $outputs.dAB_ENDPOINT_URL.value

if (-not $sqlFqdn) {
    # Fallback: iterate properties to handle any casing
    $props = $outputs.PSObject.Properties
    foreach ($p in $props) {
        switch -Wildcard ($p.Name) {
            '*SERVER_FQDN' { $sqlFqdn = $p.Value.value }
            '*SERVER_NAME' { $sqlName = $p.Value.value }
            '*DB_NAME'     { $dbName  = $p.Value.value }
            '*FUNC*NAME'   { $funcApp = $p.Value.value }
            '*STORAGE*'    { $storageName = $p.Value.value }
            '*ACR_NAME'    { $acrName = $p.Value.value }
            '*ACR_LOGIN*'  { $acrLogin = $p.Value.value }
            '*DAB_ENDPOINT*' { $dabUrl = $p.Value.value }
        }
    }
}

if (-not $sqlFqdn) {
    Write-Host "  Failed to extract outputs from Bicep deployment:" -ForegroundColor Red
    Write-Host $deployJson -ForegroundColor Red
    exit 1
}

Write-Host "  SQL: $sqlFqdn" -ForegroundColor Gray
Write-Host "  ACR: $acrLogin" -ForegroundColor Gray
Write-Host "  DAB: $dabUrl" -ForegroundColor Gray
Write-Host "  Function: $funcApp" -ForegroundColor Gray

# ── 3. Firewall rule ───────────────────────────────────
Write-Host "[3/9] Opening firewall..." -ForegroundColor Cyan
az sql server firewall-rule create --resource-group $ResourceGroup --server $sqlName `
    --name "AllowAll" --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255 --output none

# ── 4. Deploy schema + seed data via sqlpackage ───────
Write-Host "[4/9] Building + deploying database schema..." -ForegroundColor Cyan
dotnet build "$dbDir/AiDemoDb.sqlproj" --nologo -v quiet
$connStr = "Server=$sqlFqdn;Database=$dbName;User Id=$SqlAdminLogin;Password=$SqlAdminPassword;TrustServerCertificate=true;Encrypt=true;"
sqlpackage /Action:Publish /SourceFile:"$dbDir/bin/Debug/AiDemoDb.dacpac" /TargetConnectionString:"$connStr" /p:BlockOnPossibleDataLoss=false /Quiet
Write-Host "  Schema deployed (Category, Product, Customer, Review)" -ForegroundColor Green

# ── 5. Deploy Azure-SQL-only objects ──────────────────
Write-Host "[5/9] Creating external model + procs..." -ForegroundColor Cyan

Invoke-SqlFile $sqlFqdn $dbName "$dbDir/Scripts/CreateExternalModel.sql"
Write-Host "  External model registered" -ForegroundColor Green

Invoke-SqlFile $sqlFqdn $dbName "$dbDir/StoredProcedures/ChunkReviews.sql"
Invoke-SqlFile $sqlFqdn $dbName "$dbDir/StoredProcedures/EmbedReviews.sql"
Invoke-SqlFile $sqlFqdn $dbName "$dbDir/StoredProcedures/EmbedSingleReview.sql"
Invoke-SqlFile $sqlFqdn $dbName "$dbDir/StoredProcedures/ToggleChangeTracking.sql"
Invoke-SqlFile $sqlFqdn $dbName "$dbDir/StoredProcedures/ToggleVectorIndex.sql"

# VECTOR_SEARCH requires a vector index at proc compile time — create temporarily
Invoke-Sql $sqlFqdn $dbName "ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;"
Invoke-Sql $sqlFqdn $dbName "IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ReviewVector_Embedding' AND object_id = OBJECT_ID('dbo.ReviewVector')) CREATE VECTOR INDEX IX_ReviewVector_Embedding ON dbo.ReviewVector(Embedding) WITH (METRIC = 'cosine', TYPE = 'diskann');"
Invoke-SqlFile $sqlFqdn $dbName "$dbDir/StoredProcedures/SearchByVector.sql"
Invoke-SqlFile $sqlFqdn $dbName "$dbDir/StoredProcedures/SearchByText.sql"
Invoke-SqlFile $sqlFqdn $dbName "$dbDir/StoredProcedures/ResetDemo.sql"
# Drop the temporary index so the demo flow (ToggleVectorIndex) works cleanly
Invoke-Sql $sqlFqdn $dbName "DROP INDEX IX_ReviewVector_Embedding ON dbo.ReviewVector;"
Write-Host "  Stored procedures deployed" -ForegroundColor Green

Invoke-SqlFile $sqlFqdn $dbName "$dbDir/Triggers/ReviewChanged.sql"
Write-Host "  Trigger deployed" -ForegroundColor Green

Invoke-SqlFile $sqlFqdn $dbName "$dbDir/Views/ReviewsPendingEmbedding.sql"
Write-Host "  View deployed" -ForegroundColor Green

# ── 6. Build + deploy DAB container ───────────────────
Write-Host "[6/9] Building DAB container + deploying to ACA..." -ForegroundColor Cyan
az acr build --registry $acrName --image dab-api:latest "$dabDir" --no-logs

$acrPassword = (az acr credential show --name $acrName --query "passwords[0].value" -o tsv 2>$null)
az containerapp registry set --name ca-dab-api --resource-group $ResourceGroup `
    --server $acrLogin --username $acrName --password $acrPassword --output none
az containerapp update --name ca-dab-api --resource-group $ResourceGroup `
    --image "$acrLogin/dab-api:latest" --output none
Write-Host "  DAB deployed to ACA" -ForegroundColor Green

# ── 7. Set OpenAI key on Function App ─────────────────
Write-Host "[7/9] Configuring Function App secrets..." -ForegroundColor Cyan
az functionapp config appsettings set --name $funcApp --resource-group $ResourceGroup `
    --settings "OpenAI__ApiKey=$OpenAIKey" --output none

# ── 8. Publish Function ───────────────────────────────
Write-Host "[8/9] Publishing Azure Function..." -ForegroundColor Cyan
Push-Location $funcDir
dotnet publish -c Release --nologo -v quiet -o "$funcDir/publish"
Compress-Archive -Path "$funcDir/publish/*" -DestinationPath "$funcDir/publish.zip" -Force
az functionapp deployment source config-zip --name $funcApp --resource-group $ResourceGroup `
    --src "$funcDir/publish.zip" --output none
Pop-Location
Write-Host "  Function deployed" -ForegroundColor Green

# ── 9. Verify ─────────────────────────────────────────
Write-Host "[9/9] Verifying..." -ForegroundColor Cyan

# Quick query to confirm seed data
$cs = "Server=$sqlFqdn;Database=$dbName;User Id=$SqlAdminLogin;Password=$SqlAdminPassword;TrustServerCertificate=true;Encrypt=true;Connection Timeout=60;"
$c = New-Object System.Data.SqlClient.SqlConnection($cs)
$c.Open()
$cmd = $c.CreateCommand()
$cmd.CommandText = "SELECT COUNT(*) FROM dbo.Review"
$reviewCount = $cmd.ExecuteScalar()
$c.Close()
Write-Host "  Reviews in database: $reviewCount" -ForegroundColor Green

# Verify DAB health
$dabHealthy = $false
for ($i = 1; $i -le 15; $i++) {
    try {
        $resp = Invoke-RestMethod -Uri "$dabUrl/health" -TimeoutSec 10
        Write-Host "  DAB API: healthy" -ForegroundColor Green
        $dabHealthy = $true
        break
    } catch {
        Write-Host "  DAB attempt $i/15 - waiting..." -ForegroundColor Gray
        Start-Sleep -Seconds 15
    }
}
if (-not $dabHealthy) { Write-Host "  WARNING: DAB not responding" -ForegroundColor Red }

# ── Summary ───────────────────────────────────────────
Write-Host "`n════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "  SQL Server:   $sqlFqdn" -ForegroundColor Gray
Write-Host "  Database:     $dbName" -ForegroundColor Gray
Write-Host "  DAB API:      $dabUrl" -ForegroundColor Gray
Write-Host "  DAB MCP:      $dabUrl/mcp" -ForegroundColor Gray
Write-Host "  DAB Health:   $dabUrl/health" -ForegroundColor Gray
Write-Host "  Function App: $funcApp" -ForegroundColor Gray
Write-Host ""
Write-Host "  Demo steps:" -ForegroundColor White
Write-Host "    1. EXEC dbo.ChunkReviews @BatchSize = 10;" -ForegroundColor Yellow
Write-Host "    2. EXEC dbo.EmbedReviews @BatchSize = 10;" -ForegroundColor Yellow
Write-Host "    3. EXEC dbo.EmbedSingleReview @ReviewVectorId = 1;" -ForegroundColor Yellow
Write-Host "    4. EXEC dbo.ToggleChangeTracking @Enable = 1;  -- enables Function trigger" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Tear down:" -ForegroundColor White
Write-Host "    .\infra\azure-down.ps1" -ForegroundColor Yellow
Write-Host ""
