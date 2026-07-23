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

## Android Share Intent

Current dependency: `receive_sharing_intent` (^1.8.1) via [`ShareIntentService`](../apps/homeshare/lib/services/share_intent_service.dart).

**Audit (2026-07):** keep as-is while SEND / SEND_MULTIPLE intent-filters work on the target Flutter/Android SDK. Prefer replacing with `share_handler` only if Share from Files/Gallery breaks on Android 13+ (permissions / media streams). Do not swap “just in case”.

## Outbox storage

JSON per-job files under `data/outbox/` (atomic write). Drift/SQLite is deferred until concurrent-writer races are observed.

## Dependency audit

Run quarterly (or before Android SDK bumps):

```powershell
melos run deps:audit
```

Pay special attention to:

- `receive_sharing_intent` — keep while Share Intent works on the current `targetSdk`; re-test Files/Gallery share after every Android SDK upgrade.
- `tray_manager` / `window_manager` — Windows tray quirks (see AGENTS.md).

Transfer offer defaults (override in `config.json`): `max_transfer_bytes` (50 GiB), `max_manifest_entries` (10000). Disk space probe failures reject inbound offers (507 `disk_probe_failed`).
