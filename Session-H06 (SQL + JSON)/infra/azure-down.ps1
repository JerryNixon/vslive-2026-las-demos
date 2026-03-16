#!/usr/bin/env pwsh
<#
    azure-down.ps1 – Tear down Session H06 Azure resources
    ───────────────────────────────────────────────────────
    Usage:  .\infra\azure-down.ps1 [-ResourceGroup rg-h06-demo]
#>

param(
    [string]$ResourceGroup = "rg-h06-demo"
)

Write-Host "Deleting resource group $ResourceGroup..." -ForegroundColor Yellow
az group delete --name $ResourceGroup --yes --no-wait
Write-Host "Resource group deletion initiated." -ForegroundColor Green
