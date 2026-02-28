param(
    [ValidateSet("stop", "build", "run")]
    [string]$Action = "run"
)

$ErrorActionPreference = "Stop"

$appHostDir = Split-Path -Parent $PSCommandPath
$appHostProject = Join-Path $appHostDir "AppHost.csproj"

Push-Location $appHostDir
try {
    $running = Get-Process AppHost -ErrorAction SilentlyContinue
    if ($null -ne $running) {
        Write-Host "Stopping stale AppHost process(es)..."
        $running | Stop-Process -Force
        Start-Sleep -Seconds 1
    }

    switch ($Action) {
        "stop" {
            Write-Host "Done: stale AppHost processes stopped (if any)."
        }
        "build" {
            Write-Host "Building AppHost..."
            dotnet build $appHostProject -v minimal
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        "run" {
            Write-Host "Running AppHost..."
            dotnet run --project $appHostProject
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
    }
}
finally {
    Pop-Location
}
