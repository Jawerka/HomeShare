#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/apps/homeshare_server/build/homeshare-hub}"

sudo useradd -r -s /usr/sbin/nologin homeshare 2>/dev/null || true
sudo mkdir -p /etc/homeshare /var/homeshare/inbox /var/lib/homeshare
sudo cp "$ROOT/scripts/linux/config.example.json" /etc/homeshare/config.json
sudo cp "$BIN" /usr/local/bin/homeshare-hub
sudo chmod +x /usr/local/bin/homeshare-hub
sudo chown -R homeshare:homeshare /var/homeshare /var/lib/homeshare
sudo cp "$ROOT/scripts/linux/homeshare-hub.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now homeshare-hub
sudo systemctl status homeshare-hub --no-pager
echo "Web UI: http://$(hostname -I | awk '{print $1}'):8787"
