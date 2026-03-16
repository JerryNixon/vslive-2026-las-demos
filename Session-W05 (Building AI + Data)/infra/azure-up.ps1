#!/usr/bin/env pwsh
<#
    azure-up.ps1 – Deploy Session W05 (AI + Data) to Azure
    ───────────────────────────────────────────────────────
    Deploys:
      1. Azure SQL (GP Serverless) + AiDemoDb schema + seed data
      2. External model, ReviewVector table, views, procs, trigger
      3. Azure Function (EmbedOnChange) with SQL trigger binding
#>
param(
    [string]$ResourceGroup    = "rg-w05-demo",
    [string]$Location         = "centralus",
    [string]$SqlAdminLogin    = "sqladmin",
    [string]$SqlAdminPassword = $env:SQL_ADMIN_PASSWORD,
    [string]$OpenAIKey        = $env:OPENAI_KEY
)

$ErrorActionPreference = 'Stop'
$infraDir   = $PSScriptRoot
$sessionDir = Split-Path $infraDir -Parent
$dbDir      = "$sessionDir\database\AiDemoDb"
$funcDir    = "$sessionDir\function"

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
if (-not $SqlAdminPassword -or -not $OpenAIKey) {
    Write-Error "Missing secrets. Set SQL_ADMIN_PASSWORD and OPENAI_KEY in .env or pass as parameters."
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
    foreach ($batch in ($raw -split '(?m)^\s*GO\s*$')) {
        $batch = $batch.Trim()
        if ($batch.Length -gt 0) { Invoke-Sql $Server $Db $batch }
    }
}

# ── 1. Resource group ──────────────────────────────────
Write-Host "`n[1/8] Creating resource group..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none

# ── 2. Bicep deployment ────────────────────────────────
Write-Host "[2/8] Deploying infrastructure..." -ForegroundColor Cyan
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
        }
    }
}

if (-not $sqlFqdn) {
    Write-Host "  Failed to extract outputs from Bicep deployment:" -ForegroundColor Red
    Write-Host $deployJson -ForegroundColor Red
    exit 1
}

Write-Host "  SQL: $sqlFqdn" -ForegroundColor Gray
Write-Host "  Function: $funcApp" -ForegroundColor Gray

# ── 3. Firewall rule ───────────────────────────────────
Write-Host "[3/8] Adding firewall rule..." -ForegroundColor Cyan
$myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10)
az sql server firewall-rule create --resource-group $ResourceGroup --server $sqlName `
    --name "ClientIP" --start-ip-address $myIp --end-ip-address $myIp --output none

# ── 4. Deploy schema + seed data via sqlpackage ───────
Write-Host "[4/8] Building + deploying database schema..." -ForegroundColor Cyan
dotnet build "$dbDir/AiDemoDb.sqlproj" --nologo -v quiet
$connStr = "Server=$sqlFqdn;Database=$dbName;User Id=$SqlAdminLogin;Password=$SqlAdminPassword;TrustServerCertificate=true;Encrypt=true;"
sqlpackage /Action:Publish /SourceFile:"$dbDir/bin/Debug/AiDemoDb.dacpac" /TargetConnectionString:"$connStr" /p:BlockOnPossibleDataLoss=false /Quiet
Write-Host "  Schema deployed (Category, Product, Customer, Review)" -ForegroundColor Green

# ── 5. Deploy Azure-SQL-only objects ──────────────────
Write-Host "[5/8] Creating ReviewVector table + external model + procs..." -ForegroundColor Cyan
Invoke-SqlFile $sqlFqdn $dbName "$dbDir/Scripts/CreateReviewVector.sql"
Write-Host "  ReviewVector table created" -ForegroundColor Green

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

# ── 6. Set OpenAI key on Function App ─────────────────
Write-Host "[6/8] Configuring Function App secrets..." -ForegroundColor Cyan
az functionapp config appsettings set --name $funcApp --resource-group $ResourceGroup `
    --settings "OpenAI__ApiKey=$OpenAIKey" --output none

# ── 7. Publish Function ───────────────────────────────
Write-Host "[7/8] Publishing Azure Function..." -ForegroundColor Cyan
Push-Location $funcDir
dotnet publish -c Release --nologo -v quiet -o "$funcDir/publish"
Compress-Archive -Path "$funcDir/publish/*" -DestinationPath "$funcDir/publish.zip" -Force
az functionapp deployment source config-zip --name $funcApp --resource-group $ResourceGroup `
    --src "$funcDir/publish.zip" --output none
Pop-Location
Write-Host "  Function deployed" -ForegroundColor Green

# ── 8. Verify ─────────────────────────────────────────
Write-Host "[8/8] Verifying..." -ForegroundColor Cyan

# Quick query to confirm seed data
$cs = "Server=$sqlFqdn;Database=$dbName;User Id=$SqlAdminLogin;Password=$SqlAdminPassword;TrustServerCertificate=true;Encrypt=true;Connection Timeout=60;"
$c = New-Object System.Data.SqlClient.SqlConnection($cs)
$c.Open()
$cmd = $c.CreateCommand()
$cmd.CommandText = "SELECT COUNT(*) FROM dbo.Review"
$reviewCount = $cmd.ExecuteScalar()
$c.Close()
Write-Host "  Reviews in database: $reviewCount" -ForegroundColor Green

# ── Summary ───────────────────────────────────────────
Write-Host "`n════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "  SQL Server:   $sqlFqdn" -ForegroundColor Gray
Write-Host "  Database:     $dbName" -ForegroundColor Gray
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
