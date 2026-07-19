# HomeShare setup (Windows developer machine)
$ErrorActionPreference = "Stop"
$Flutter = "$env:LOCALAPPDATA\flutter\bin"
if (Test-Path "$Flutter\flutter.bat") {
  $env:Path = "$Flutter;$env:Path"
}

Write-Host "Flutter:"
flutter --version

Write-Host "Activating melos..."
dart pub global activate melos

Write-Host "Bootstrap workspace..."
Set-Location $PSScriptRoot\..
dart pub get
melos bootstrap

Write-Host "Done. Run .\dev.ps1 to start Windows app."
