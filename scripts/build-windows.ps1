$ErrorActionPreference = "Stop"
$env:Path = "$env:LOCALAPPDATA\flutter\bin;$env:Path"
$Root = Split-Path $PSScriptRoot -Parent
$Version = if ($env:HOMESHARE_VERSION) { $env:HOMESHARE_VERSION } else { "0.1.1" }
Push-Location "$Root\apps\homeshare"
try {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  $Out = "$Root\dist\windows"
  New-Item -ItemType Directory -Force -Path $Out | Out-Null
  $ReleaseDir = "build\windows\x64\runner\Release"
  # Avoid packaging previous Inno output if it landed in this folder.
  Remove-Item "$Out\*setup*.exe" -Force -ErrorAction SilentlyContinue
  Copy-Item -Recurse -Force "$ReleaseDir\*" $Out
} finally {
  Pop-Location
}

# Shell extension DLL (context menu submenu)
& "$Root\scripts\build-shell-dll.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Copy-Item -Force "$Root\native\windows_shell\HomeShareShell.dll" "$Root\dist\windows\HomeShareShell.dll"

$Iss = "$Root\scripts\windows\homeshare.iss"
if (Test-Path $Iss) {
  $iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($iscc) {
    (Get-Content $Iss) -replace '#define MyAppVersion ".*"', "#define MyAppVersion `"$Version`"" | Set-Content $Iss
    & $iscc $Iss
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  } else {
    Write-Warning "Inno Setup 6 not found - zip only."
  }
}

Compress-Archive -Path "$Root\dist\windows\*" -DestinationPath "$Root\dist\homeshare-$Version-windows-x64.zip" -Force
Write-Host "Windows build ready in dist/ (version $Version)"
