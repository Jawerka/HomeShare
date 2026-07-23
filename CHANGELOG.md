# Changelog

## 0.1.1 — hardening

- PR CI (`ci.yml`) + GitHub Releases on tag `v*` (hub, Windows, APK)
- Centralized logging (`HsLog`); quieter silent catches log warnings
- Expanded core/p2p tests: resume, auth 401, disk_full, outbox reload/corrupt
- Outbox cancel/retry; JSON outbox confirmed (Drift deferred)
- AppController extracts: `LocalAgentServer`, `PendingSendQueue`, `WindowShell`
- UX polish: teal theme, empty states, PIN copy, revoke confirm, transfer actions
- Threat model docs: PIN pairing sufficient (`docs/SECURITY.md`)
- Local `AGENTS.md` (gitignored) for agent guidance

## 0.1.0 — initial scaffold

- Monorepo: `homeshare_core`, `homeshare_p2p`, Flutter app, Linux server
- Pairing PIN/QR, UDP discovery, chunked file/dir transfer with SHA-256
- Auto-accept into inbox with disk-space pre-check
- Windows tray progress %, local agent for shell extension
- Android Share Intent + notification progress
- Linux Web UI on :8787 (MeshPad Hub style)
- COM shell extension source + Inno/systemd scripts
- Package tests for core + P2P e2e
