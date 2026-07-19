# Linux Hub

Headless HomeShare peer with Web UI on port **8787**.

## Config

`/etc/homeshare/config.json` (see `scripts/linux/config.example.json`):

- `inbox_dir` — where received files are stored (change via file + restart; Web UI is read-only for this path)
- `web_port` — default 8787
- `p2p_port` — default 45838
- `discovery_port` — default 45837
- `data_dir` — identity, tokens, trusted peers

## Web UI API

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | Single-page UI |
| GET | `/hub/status` | PIN, devices, events, free space |
| POST | `/hub/pairing/refresh` | New PIN |
| GET | `/hub/qr.svg` | Pairing QR SVG |
| POST | `/hub/devices/<id>/revoke` | Unpair |
| POST | `/hub/devices/revoke-all` | Unpair all |

## CLI send

```bash
homeshare-hub send --to <peer_id_or_name> /path/to/file
```

## Install

```bash
dart compile exe bin/homeshare_server.dart -o homeshare-hub
sudo ./scripts/linux/install-hub-ubuntu.sh ./homeshare-hub
```

Requires `avahi-daemon` for mDNS on many distros; UDP beacon still works without it.
