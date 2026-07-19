#Requires -Version 5.1
<#
.SYNOPSIS
  Create HomeShare Android release keystore and local key.properties.

.DESCRIPTION
  One-time setup so local release builds use a fixed APK signing key.
  Writes apps/homeshare/android/homeshare-release.keystore and key.properties (gitignored).
  Updates scripts/android-release-cert-sha256.txt for verification.

.PARAMETER Force
  Regenerate keystore even if it already exists (invalidates prior release APK signatures).

.PARAMETER SkipGitHub
  Only create local keystore/key.properties; do not push secrets to GitHub.

.EXAMPLE
  .\scripts\setup-android-signing.ps1 -SkipGitHub
#>
param(
    [switch] $Force,
    [switch] $SkipGitHub
)

$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$androidDir = Join-Path $root "apps\homeshare\android"
$keystore = Join-Path $androidDir "homeshare-release.keystore"
$keyProps = Join-Path $androidDir "key.properties"
$fingerprintFile = Join-Path $PSScriptRoot "android-release-cert-sha256.txt"
$keyAlias = "homeshare"
$validityDays = 10000

$keytool = Join-Path ${env:ProgramFiles} "Android\Android Studio\jbr\bin\keytool.exe"
if (-not (Test-Path $keytool)) {
    $keytoolCmd = Get-Command keytool -ErrorAction SilentlyContinue
    if ($keytoolCmd) {
        $keytool = $keytoolCmd.Source
    } else {
        throw "keytool not found. Install Android Studio JBR or JDK."
    }
}

function New-RandomPassword {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-ReleaseCertSha256 {
    param([string] $KeystorePath, [string] $StorePassword, [string] $Alias)
    $output = & $keytool -list -v -keystore $KeystorePath -storepass $StorePassword -alias $Alias 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "keytool -list failed: $output"
    }
    $line = $output | Where-Object { $_ -match 'SHA256:' } | Select-Object -First 1
    if (-not $line) {
        throw "SHA256 fingerprint not found in keytool output"
    }
    return ($line -replace '.*SHA256:\s*', '').Trim()
}

if (-not (Test-Path $androidDir)) {
    throw "Android dir not found: $androidDir"
}

if ((Test-Path $keystore) -and -not $Force) {
    Write-Host "Keystore already exists: $keystore"
    Write-Host "Use -Force to regenerate (breaks upgrade path from older release APKs)."
} else {
    if (Test-Path $keystore) { Remove-Item -Force $keystore }
    if (Test-Path $keyProps) { Remove-Item -Force $keyProps }

    $storePassword = New-RandomPassword
    $keyPassword = $storePassword

    Write-Host "Generating HomeShare release keystore..."
    $dname = "CN=HomeShare, OU=Engineering, O=HomeShare, L=Local, ST=Local, C=RU"
    & $keytool -genkeypair -v `
        -keystore $keystore `
        -alias $keyAlias `
        -keyalg RSA `
        -keysize 2048 `
        -validity $validityDays `
        -storepass $storePassword `
        -keypass $keyPassword `
        -dname $dname
    if ($LASTEXITCODE -ne 0) {
        throw "keytool -genkeypair failed with exit code $LASTEXITCODE"
    }

    $lines = @(
        "storePassword=$storePassword"
        "keyPassword=$keyPassword"
        "keyAlias=$keyAlias"
        "storeFile=../homeshare-release.keystore"
    )
    [System.IO.File]::WriteAllLines(
        $keyProps,
        $lines,
        (New-Object System.Text.UTF8Encoding $false)
    )

    Write-Host "Wrote $keyProps"
}

$props = @{}
Get-Content $keyProps | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
    $parts = $_ -split '=', 2
    $props[$parts[0].Trim()] = $parts[1].Trim()
}

$storePassword = $props['storePassword']
$keyPassword = $props['keyPassword']
$keyAlias = $props['keyAlias']

$sha256 = Get-ReleaseCertSha256 -KeystorePath $keystore -StorePassword $storePassword -Alias $keyAlias
$sha256Hex = ($sha256 -replace ':', '').ToLowerInvariant()
[System.IO.File]::WriteAllText($fingerprintFile, $sha256Hex, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Certificate SHA-256: $sha256"
Write-Host "Wrote $fingerprintFile"

if ($SkipGitHub) {
    Write-Host "Skipped GitHub secrets (-SkipGitHub)."
    Write-Host ""
    Write-Host "Android release signing configured." -ForegroundColor Green
    Write-Host "  Local keystore: $keystore"
    Write-Host "  Local config:   $keyProps"
    Write-Host "  Fingerprint:    $fingerprintFile"
    exit 0
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) not found. Install gh or rerun with -SkipGitHub."
}

$keystoreBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))

Write-Host "Setting GitHub repository secrets..."
gh secret set ANDROID_KEYSTORE_BASE64 --body $keystoreBase64
gh secret set ANDROID_STORE_PASSWORD --body $storePassword
gh secret set ANDROID_KEY_PASSWORD --body $keyPassword
gh secret set ANDROID_KEY_ALIAS --body $keyAlias

Write-Host ""
Write-Host "Android release signing configured." -ForegroundColor Green
Write-Host "  Local keystore: $keystore"
Write-Host "  Local config:   $keyProps"
Write-Host "  Fingerprint:    $fingerprintFile"
