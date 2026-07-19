; Inno Setup 6 script for HomeShare
#define MyAppName "HomeShare"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "HomeShare"
#define MyAppExeName "homeshare.exe"

[Setup]
AppId={{A7F3C2E1-HOME-SHARE-SETUP-0001}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\HomeShare
DefaultGroupName=HomeShare
OutputDir=..\..\dist
OutputBaseFilename=homeshare-{#MyAppVersion}-windows-x64-setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin

[Files]
Source: "..\..\dist\windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs; Excludes: "*setup.exe"
Source: "..\..\native\windows_shell\HomeShareShell.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\..\scripts\allow-homeshare-firewall.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\HomeShare"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--background"
Name: "{autodesktop}\HomeShare"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--background"
Name: "{userstartup}\HomeShare"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--background"

[Registry]
; Remove legacy static verb (no submenu)
Root: HKCU; Subkey: "Software\Classes\*\shell\HomeShare"; Flags: deletekey uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\HomeShare"; Flags: deletekey uninsdeletekey

; COM context menu with dynamic peer submenu ({{ = escaped {)
Root: HKCU; Subkey: "Software\Classes\CLSID\{{A7F3C2E1-9B4D-4E8A-B1C0-1234567890AB}}"; ValueType: string; ValueName: ""; ValueData: "HomeShare Context Menu"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\CLSID\{{A7F3C2E1-9B4D-4E8A-B1C0-1234567890AB}}\InprocServer32"; ValueType: string; ValueName: ""; ValueData: "{app}\HomeShareShell.dll"
Root: HKCU; Subkey: "Software\Classes\CLSID\{{A7F3C2E1-9B4D-4E8A-B1C0-1234567890AB}}\InprocServer32"; ValueType: string; ValueName: "ThreadingModel"; ValueData: "Apartment"
Root: HKCU; Subkey: "Software\Classes\*\shellex\ContextMenuHandlers\HomeShare"; ValueType: string; ValueName: ""; ValueData: "{{A7F3C2E1-9B4D-4E8A-B1C0-1234567890AB}}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shellex\ContextMenuHandlers\HomeShare"; ValueType: string; ValueName: ""; ValueData: "{{A7F3C2E1-9B4D-4E8A-B1C0-1234567890AB}}"; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--background"; Description: "Запустить HomeShare в трее"; Flags: nowait postinstall skipifsilent
Filename: "{sys}\regsvr32.exe"; Parameters: "/s ""{app}\HomeShareShell.dll"""; Flags: runhidden; StatusMsg: "Регистрация контекстного меню…"
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\allow-homeshare-firewall.ps1"""; Flags: runhidden; Description: "Firewall rules"

[UninstallRun]
Filename: "{sys}\regsvr32.exe"; Parameters: "/s /u ""{app}\HomeShareShell.dll"""; Flags: runhidden
