$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$configDirectory = Join-Path -Path $projectRoot -ChildPath "config"
$configPath = Join-Path -Path $configDirectory -ChildPath "routes.json"

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing routes configuration. Run the route configuration script first."
}

Push-Location $projectRoot

try {
    flutter run "--dart-define-from-file=$configPath"
} finally {
    Pop-Location
}