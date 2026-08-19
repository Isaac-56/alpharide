$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$configDirectory = Join-Path $projectRoot "config"
$configPath = Join-Path $configDirectory "routes.json"

$routeKey = (Read-Host "Paste the Google Routes API key now").Trim().Trim('"').Trim("'")

if (-not $routeKey.StartsWith("AIza")) {
    throw "The value does not look like a Google API key. Copy the full key beginning with AIza and run this script again."
}

$certificateSha1 = (Read-Host "Android SHA-1 (press Enter to use the current debug SHA-1)").Trim()

if ([string]::IsNullOrWhiteSpace($certificateSha1)) {
    $certificateSha1 = "3A:6A:84:46:2B:B9:85:F1:1C:6A:F8:4A:E9:61:E3:B9:DE:25:B5:C4"
}

New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null

$config = [ordered]@{
    GOOGLE_ROUTES_API_KEY = $routeKey
    GOOGLE_ANDROID_CERT_SHA1 = $certificateSha1
} | ConvertTo-Json

$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $config + [Environment]::NewLine, $utf8WithoutBom)

Write-Host "Created $configPath"
Write-Host "In VS Code choose: AlphaRide (Android with routing)"
