$ErrorActionPreference = "Stop"
$env:Path = "$env:LOCALAPPDATA\flutter\bin;$env:Path"
Set-Location $PSScriptRoot\..
dart pub get
if (Get-Command melos -ErrorAction SilentlyContinue) {
  melos bootstrap
} else {
  Push-Location packages\homeshare_core; dart pub get; Pop-Location
  Push-Location packages\homeshare_p2p; dart pub get; Pop-Location
  Push-Location apps\homeshare_server; dart pub get; Pop-Location
  Push-Location apps\homeshare; flutter pub get; Pop-Location
}
Write-Host "Bootstrap complete."
