# Architecture

HomeShare is a LAN peer-to-peer file transfer system.

```
┌────────────┐   mDNS/UDP    ┌────────────┐
│  Windows   │◄────────────►│  Android   │
│  Flutter   │   HTTP:45838 │  Flutter   │
└─────┬──────┘              └─────┬──────┘
      │                           │
      └──────────┬────────────────┘
                 │
          ┌──────▼──────┐
          │ Linux hub   │
          │ Web :8787   │
          │ P2P :45838  │
          └─────────────┘
```

## Packages

- **homeshare_core** — no Flutter: models, outbox, SHA-256 streaming, disk space, inbox writer, identity/tokens.
- **homeshare_p2p** — UDP discovery, PIN pairing, shelf HTTP peer server, transfer client/coordinator.
- **apps/homeshare** — UI + tray + agent + Share Intent.
- **apps/homeshare_server** — headless peer + embedded Web UI.

## Trust model

1. Discovery finds neighbours (not trusted).
2. Pairing (PIN/QR) exchanges `auth_token` and stores `TrustedPeer`.
3. Transfer endpoints require peer id + token.
4. 401/403 → re-pair UX; peer stays in discovery cache.

## Delivery contract

- Outbox on disk; jobs survive restart.
- Ack/`completed` only after receiver SHA-256 verify.
- `TransportException` does not burn retries.
- Auto-accept: no user confirm on receive; files land in inbox.
