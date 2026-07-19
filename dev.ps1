param(
  [switch]$Test,
  [switch]$WithFormat,
  [switch]$Release,
  [string]$Device = "windows"
)

$ErrorActionPreference = "Stop"
$env:Path = "$env:LOCALAPPDATA\flutter\bin;$env:Path"
Set-Location $PSScriptRoot

if ($Test) {
  Push-Location packages\homeshare_core; dart test; Pop-Location
  Push-Location packages\homeshare_p2p; dart test; Pop-Location
  if ($WithFormat) {
    dart format --set-exit-if-changed packages apps
  }
  exit 0
}

if ($Release) {
  & .\scripts\build-windows.ps1
  exit 0
}

Set-Location apps\homeshare
flutter run -d $Device
