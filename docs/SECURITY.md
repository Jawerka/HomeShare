# Security notes

## Threat model

HomeShare is for a **trusted LAN** (home / small office). Pairing by short-lived **PIN** (and optional QR) is enough to establish trust between devices. We intentionally do **not** require:

- OS secure storage / Keystore for tokens
- Extra auth on the Windows localhost agent (`127.0.0.1` bind is enough)
- Ed25519 upgrade or TLS / certificate pinning for P2P

Plaintext `tokens.json` and `identity.json` under `data_dir` on the device is acceptable for this model.

## What we do enforce

- LAN-only by design. Do not expose ports 45838/8787 to the internet without reverse proxy + TLS + auth.
- Pairing PIN is short-lived (≈2 min) and single-guest.
- Auth tokens stored in `tokens.json` under `data_dir`, separate from public `trusted_peers.json`.
- Request signing uses HMAC-SHA256 over device seed (portable stand-in; Ed25519 is not a current goal).
- Path sanitization rejects `..`, absolute paths, NUL.
- Disk space checked before accept; mid-write failures abort and clean temp.
- SHA-256 verify before transfer completes.
- Windows shell extension only talks to `127.0.0.1` with a short timeout.
