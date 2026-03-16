#!/usr/bin/env pwsh
<#
    azure-down.ps1 – Tear down Session W05 Azure resources
#>
param(
    [string]$ResourceGroup = "rg-w05-demo"
)

Write-Host "Deleting resource group $ResourceGroup..." -ForegroundColor Yellow
az group delete --name $ResourceGroup --yes --no-wait
Write-Host "Resource group deletion initiated." -ForegroundColor Green
