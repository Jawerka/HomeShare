$ErrorActionPreference = "Stop"
$env:Path = "$env:LOCALAPPDATA\flutter\bin;$env:Path"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
# Keep pub-cache on same drive as the project (Kotlin incremental cross-root bug)
if (-not $env:PUB_CACHE) {
  $env:PUB_CACHE = "D:\Documents\Projects\.pub-cache"
  New-Item -ItemType Directory -Force -Path $env:PUB_CACHE | Out-Null
}

$Root = Split-Path $PSScriptRoot -Parent
Set-Location "$Root\apps\homeshare"

$keyProps = Join-Path $Root "apps\homeshare\android\key.properties"
if (-not (Test-Path $keyProps)) {
    Write-Host "WARNING: android/key.properties not found - APK will be debug-signed." -ForegroundColor Yellow
    Write-Host "Run .\scripts\setup-android-signing.ps1 -SkipGitHub" -ForegroundColor Yellow
}

flutter build apk --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Out = "$Root\dist\android"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$Out\homeshare-0.1.0.apk" -Force
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$Out\homeshare.apk" -Force
Write-Host "APK: $Out\homeshare-0.1.0.apk"
