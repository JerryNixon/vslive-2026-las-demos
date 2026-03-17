#!/usr/bin/env pwsh
<#
    azure-verify.ps1 – Verify Session W05 (AI + Data) Azure resources
    ─────────────────────────────────────────────────────────────────
    Checks:
      1. Resource group exists
      2. Azure SQL database is online
      3. Function App is running with EmbedOnChange deployed
      4. DAB Container App is healthy (REST + MCP)
#>
param(
    [string]$ResourceGroup = "rg-w05-demo"
)

$ErrorActionPreference = 'Stop'
$pass = 0
$fail = 0

function Check($Name, [scriptblock]$Test) {
    try {
        $result = & $Test
        if ($result) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            $script:fail++
        }
    } catch {
        Write-Host "  [FAIL] $Name — $($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "`nVerifying W05 demo resources..." -ForegroundColor Cyan

# 1. Resource group
Check "Resource group '$ResourceGroup'" {
    $rg = az group show --name $ResourceGroup -o json 2>$null | ConvertFrom-Json
    $rg.properties.provisioningState -eq 'Succeeded'
}

# 2. SQL Server + Database
$sqlName = az resource list --resource-group $ResourceGroup --resource-type "Microsoft.Sql/servers" --query "[0].name" -o tsv 2>$null
$dbName  = az sql db list --server $sqlName --resource-group $ResourceGroup --query "[?name!='master'].name | [0]" -o tsv 2>$null

Check "SQL Server '$sqlName'" {
    $null -ne $sqlName -and $sqlName.Length -gt 0
}

Check "Database '$dbName' is online" {
    $db = az sql db show --server $sqlName --resource-group $ResourceGroup --name $dbName -o json 2>$null | ConvertFrom-Json
    $db.status -eq 'Online'
}

# 3. Function App
$funcName = az resource list --resource-group $ResourceGroup --resource-type "Microsoft.Web/sites" --query "[0].name" -o tsv 2>$null

Check "Function App '$funcName' is running" {
    $func = az functionapp show --name $funcName --resource-group $ResourceGroup -o json 2>$null | ConvertFrom-Json
    $func.state -eq 'Running'
}

Check "EmbedOnChange function deployed" {
    $functions = az functionapp function list --name $funcName --resource-group $ResourceGroup --query "[].name" -o json 2>$null | ConvertFrom-Json
    $functions -match 'EmbedOnChange'
}

# 4. DAB Container App
$dabFqdn = az containerapp show --name ca-dab-api --resource-group $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv 2>$null

Check "DAB Container App FQDN resolves" {
    $null -ne $dabFqdn -and $dabFqdn.Length -gt 0
}

Check "DAB /health is Healthy" {
    $health = Invoke-RestMethod -Uri "https://$dabFqdn/health" -TimeoutSec 15
    $health.status -eq 'Healthy'
}

Check "DAB MCP enabled" {
    $health = Invoke-RestMethod -Uri "https://$dabFqdn/health" -TimeoutSec 15
    $health.configuration.mcp -eq $true
}

# Summary
Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan

if ($fail -eq 0) {
    Write-Host "`n  DAB API:    https://$dabFqdn" -ForegroundColor Gray
    Write-Host "  DAB Health: https://$dabFqdn/health" -ForegroundColor Gray
    Write-Host "  DAB MCP:    https://$dabFqdn/mcp" -ForegroundColor Gray
    Write-Host "  Function:   $funcName" -ForegroundColor Gray
    Write-Host ""
}

exit $fail
