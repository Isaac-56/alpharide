$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectRoot "configoutes.json"

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing configoutes.json. Run .	oolconfigure_routes.ps1 first."
}

Push-Location $projectRoot

try {
    flutter run "--dart-define-from-file=$configPath"
} finally {
    Pop-Location
}
