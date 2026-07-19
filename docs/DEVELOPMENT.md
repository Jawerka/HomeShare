# Development

## Prerequisites

- Flutter stable (see `.fvmrc`)
- Visual Studio 2022+ with C++ desktop + ATL (Windows)
- Android SDK + JDK (Android)
- Inno Setup 6 (Windows installer)
- Dart SDK (Linux hub AOT)

## Commands

```powershell
.\scripts\setup.ps1
.\scripts\bootstrap.ps1
.\dev.ps1 -Test
.\scripts\build-windows.ps1
.\scripts\build-android.ps1
.\scripts\allow-homeshare-firewall.ps1
```

```bash
cd packages/homeshare_core && dart test
cd packages/homeshare_p2p && dart test
cd apps/homeshare_server && dart run bin/homeshare_server.dart
```

## Dual-device LAN debug

1. Start hub or Windows app on machine A.
2. Pair Android/Windows B via PIN.
3. Send a file; watch Transfers screen / notification / tray `%`.
4. Kill mid-transfer; restart; confirm resume.
