# TRANSFER_WIRE v1

Prefix: `/homeshare/p2p`

## Headers

| Header | Purpose |
|--------|---------|
| `X-HomeShare-Peer-Id` | Sender peer id |
| `X-HomeShare-Auth-Token` | Shared auth token from pairing |
| `X-HomeShare-Timestamp` | Unix ms (mutations) |
| `X-HomeShare-Signature` | HMAC-SHA256 over canonical payload |
| `X-HomeShare-Path` | Relative path inside transfer |
| `X-HomeShare-Upload-Offset` | Byte offset |
| `X-HomeShare-Upload-Total` | Total bytes for current file |
| `X-HomeShare-Upload-Sha256` | Optional per-file hash |

## Pairing

### `GET /homeshare/p2p/pairing/offer`

```json
{
  "offer_id": "uuid",
  "pin": "123456",
  "display_name": "Bob",
  "peer_id": "…",
  "http_port": 45838,
  "qr": "homeshare://pair?host=…&port=45838&pin=123456"
}
```

### `POST /homeshare/p2p/pairing/confirm`

Body: `{ offer_id, pin, peer_id, display_name, signing_public_key }`

Response: `{ auth_token, peer_id, display_name, signing_public_key, http_port }`

One guest per active offer. PIN TTL ≈ 2 minutes.

## Transfer (auto-accept)

### `POST /homeshare/p2p/transfer/offer`

```json
{
  "transfer_id": "uuid",
  "name": "video.mp4",
  "kind": "file",
  "size": 5242880000,
  "sha256": "hex",
  "file_count": 1,
  "manifest": null
}
```

For directories: `kind: "dir"` and `manifest: [{ path, size, sha256 }]`.

**200** `{ status: "ready", resume_offset, inbox_free_bytes }`  
**507** `disk_full`  
**401/403** auth  
**400** `path_invalid`

Receiver checks free space: `required + max(64MiB, 1%)`.

### `PUT /homeshare/p2p/transfer/<id>/blob`

Body: raw bytes. Headers: Content-Range / upload offset / path.

### `POST /homeshare/p2p/transfer/<id>/finalize`

Body: `{ sha256 }` for files. Verifies hash, atomic move into inbox.

### `GET /homeshare/p2p/transfer/<id>/status`

Progress JSON for debugging/UI.

## Temp files

Written under `<inbox>/.homeshare-tmp/<transfer_id>/` then renamed into inbox.
