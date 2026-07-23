# HomeShare

Кроссплатформенный обмен файлами в локальной сети (LAN-only, peer-to-peer).

| Платформа | Роль |
|-----------|------|
| **Windows** | Flutter UI + tray + контекстное меню Explorer |
| **Android** | Flutter UI + Share Intent + уведомления с прогрессом |
| **Linux** | Headless hub + Web UI (`:8787`) + CLI send |

Все устройства равноправны. После pairing файлы уходят сразу, без подтверждения на приёме.

## Быстрый старт (разработка)

```powershell
.\scripts\setup.ps1
.\scripts\bootstrap.ps1
.\dev.ps1                # Windows
.\dev.ps1 -Test          # unit/e2e тесты core+p2p
```

Linux hub:

```bash
cd apps/homeshare_server
dart pub get
dart run bin/homeshare_server.dart --config ./config.json
# Web UI → http://<lan-ip>:8787
```

## Структура

```
packages/homeshare_core   # models, outbox, hash, disk, crypto
packages/homeshare_p2p    # discovery, pairing, transfer HTTP
apps/homeshare            # Flutter Windows/Android
apps/homeshare_server     # Linux AOT + Web UI
native/windows_shell      # COM context menu
docs/                     # ARCHITECTURE, TRANSFER_WIRE, …
```

Подробный план: [PLAN.md](PLAN.md). Исходный roadmap MeshPad: [roadmap.md](roadmap.md).

## Порты

| Порт | Назначение |
|------|------------|
| 45837/udp | Discovery beacon |
| 45838/tcp | Pairing + transfer |
| 8787/tcp | Linux Web UI |
| 47831/tcp | Windows local agent (shell) |

Firewall: `.\scripts\allow-homeshare-firewall.ps1` (от администратора).

## Releases

Сборки публикуются в [GitHub Releases](https://github.com/Jawerka/HomeShare/releases) по тегу `v*` (например `v0.1.0`):

| Артефакт | Платформа |
|----------|-----------|
| `homeshare-hub-linux-x64-*.tar.gz` | Linux hub |
| `homeshare-*-windows-x64.zip` / `*-setup.exe` | Windows |
| `homeshare-*.apk` | Android (подпись через repository secrets) |

CI на каждый PR: analyze + unit/e2e тесты + сборка shell DLL. Workflows: `.github/workflows/ci.yml`, `.github/workflows/build-release.yml`.

Совместимость: Windows 10/11, Android 10+, Ubuntu 22.04+. Статус разработки: [PLAN.md](PLAN.md).
