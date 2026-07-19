# Security notes

- LAN-only. Do not expose ports 45838/8787 to the internet without reverse proxy + TLS + auth.
- Pairing PIN is short-lived (≈2 min) and single-guest.
- Auth tokens stored in `tokens.json` under `data_dir`, separate from public `trusted_peers.json`.
- Signing uses HMAC-SHA256 over device seed (portable stand-in; upgrade path to Ed25519).
- Path sanitization rejects `..`, absolute paths, NUL.
- Disk space checked before accept; mid-write failures abort and clean temp.
- Windows shell extension only talks to `127.0.0.1` with a short timeout.
