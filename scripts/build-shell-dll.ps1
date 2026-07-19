$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$ShellDir = Join-Path $Root "native\windows_shell"
$OutDll = Join-Path $ShellDir "HomeShareShell.dll"
$DistDll = Join-Path $Root "dist\windows\HomeShareShell.dll"

$vcvars = @(
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
  "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $vcvars) {
  throw "vcvars64.bat not found. Install VS Build Tools with C++ workload."
}

$bat = Join-Path $env:TEMP "homeshare-build-shell.bat"
@"
@echo off
call "$vcvars" || exit /b 1
cd /d "$ShellDir" || exit /b 1
cl /nologo /LD /O2 /EHsc /utf-8 /DUNICODE /D_UNICODE /W3 HomeShareShell.cpp /link /DEF:HomeShareShell.def ole32.lib shell32.lib shlwapi.lib winhttp.lib user32.lib advapi32.lib /OUT:HomeShareShell.dll
exit /b %ERRORLEVEL%
"@ | Set-Content -Encoding ASCII $bat

cmd /c $bat
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

New-Item -ItemType Directory -Force -Path (Split-Path $DistDll) | Out-Null
Copy-Item -Force $OutDll $DistDll
Write-Host "Built $OutDll"
Write-Host "Copied $DistDll"
