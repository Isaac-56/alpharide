param([string]$ProjectsRoot = 'C:\Projects')
$ErrorActionPreference = 'Stop'
$apps = @(
    @{ Repo = (Join-Path $ProjectsRoot 'Alpha'); Name = 'AlphaRide.apk' },
    @{ Repo = (Join-Path $ProjectsRoot 'alpha_plus'); Name = 'AlphaPlus.apk' }
)
function Assert-Command([string]$Message) {
    if ($LASTEXITCODE -ne 0) { throw $Message }
}
foreach ($app in $apps) {
    Set-Location $app.Repo
    git -c http.version=HTTP/1.1 -c http.lowSpeedLimit=100 -c http.lowSpeedTime=60 -c gc.auto=0 -c maintenance.auto=false fetch --no-tags origin '+refs/heads/feat/bird-whatsapp-otp:refs/remotes/origin/feat/bird-whatsapp-otp'
    Assert-Command 'Fetch failed. Local files were kept; retry when your connection is stable.'
    git switch --detach origin/feat/bird-whatsapp-otp
    Assert-Command 'Checkout failed. Keep local changes and send the error; do not reset or discard them.'
    if (-not (Test-Path 'android\key.properties')) { throw "Existing release signing configuration is missing in $($app.Repo)." }
}
Set-Location $apps[0].Repo
node --test tool/test/repair_android_release.test.cjs
Assert-Command 'Release configuration tool tests failed.'
# Uses the existing signed APKs to verify the expected certificate before changes.
node tool/repair_android_release.cjs $ProjectsRoot --apply
Assert-Command 'Release configuration needs attention. Stop here and send the short error above.'

npm --prefix functions ci
Assert-Command 'Backend dependency installation failed.'
firebase deploy --only 'functions:passengerSearchPlaces' --project alpha-ride-29708
Assert-Command 'First-letter search backend deployment failed.'

foreach ($app in $apps) {
    Set-Location (Join-Path $app.Repo 'android')
    .\gradlew.bat --stop
    Assert-Command 'Could not stop the Gradle daemon.'
    $propertiesPath = Join-Path $PWD 'gradle.properties'
    $backupPath = "$propertiesPath.before-release-fix"
    if (-not (Test-Path $backupPath)) { Copy-Item $propertiesPath $backupPath }
    $settings = Get-Content $propertiesPath -Raw
    $settings = $settings -replace '(?m)^\s*org\.gradle\.(jvmargs|workers\.max|parallel)\s*=.*\r?\n?', ''
    $settings += "`r`norg.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G`r`norg.gradle.workers.max=2`r`norg.gradle.parallel=false`r`n"
    [IO.File]::WriteAllText($propertiesPath, $settings)
    Set-Location $app.Repo
    flutter build apk --release --dart-define=ALPHA_APP_CHECK_DEBUG=false
    Assert-Command "Release build failed for $($app.Name)."
}
Set-Location $apps[0].Repo
node tool/repair_android_release.cjs $ProjectsRoot --verify-signatures
Assert-Command 'New APK signatures do not match the expected release certificate.'
$releaseFolder = Join-Path ([Environment]::GetFolderPath('Desktop')) ('Alpha-Release-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $releaseFolder | Out-Null
foreach ($app in $apps) {
    Copy-Item (Join-Path $app.Repo 'build\app\outputs\flutter-apk\app-release.apk') (Join-Path $releaseFolder $app.Name)
}
Write-Host 'Both signed APKs are ready for your brother to test. Device attestation and map delivery are not yet confirmed.'
Invoke-Item $releaseFolder
