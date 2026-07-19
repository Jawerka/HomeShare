/// Embedded single-page Web UI (MeshPad Hub style) for HomeShare.
String webUiHtml({required String version}) {
  return '''
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>HomeShare Hub</title>
  <style>
    :root {
      color-scheme: light dark;
      font-family: system-ui, -apple-system, sans-serif;
      --bg: #f4f4f5; --card: #fff; --text: #111; --muted: #666;
      --ok: #16a34a; --warn: #ca8a04; --err: #dc2626; --wait: #64748b;
    }
    @media (prefers-color-scheme: dark) {
      :root { --bg: #18181b; --card: #27272a; --text: #fafafa; --muted: #a1a1aa; }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; min-height: 100vh; background: var(--bg); color: var(--text);
      display: flex; align-items: flex-start; justify-content: center; padding: 1rem;
    }
    main {
      width: 100%; max-width: 420px; background: var(--card);
      border-radius: 16px; padding: 1.25rem 1.5rem 1.5rem;
      box-shadow: 0 4px 24px rgba(0,0,0,.08);
    }
    h1 { font-size: 1.35rem; margin: 0 0 .2rem; text-align: center; }
    .sub { color: var(--muted); font-size: .9rem; margin-bottom: .75rem; text-align: center; }
    .badge {
      display: flex; align-items: center; gap: .55rem;
      padding: .65rem .85rem; border-radius: 10px; font-size: .88rem;
      margin-bottom: 1rem; background: rgba(128,128,128,.08);
    }
    .dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
    .dot.ok { background: var(--ok); }
    .dot.partial { background: var(--warn); }
    .dot.error { background: var(--err); }
    .dot.waiting, .dot.idle, .dot.syncing { background: var(--wait); }
    .dot.syncing { animation: pulse 1s infinite alternate; }
    @keyframes pulse { from { opacity: .35; } to { opacity: 1; } }
    .stats {
      display: grid; grid-template-columns: 1fr 1fr 1fr; gap: .5rem;
      margin-bottom: 1rem; text-align: center; font-size: .78rem; color: var(--muted);
    }
    .stats strong { display: block; font-size: 1.15rem; color: var(--text); }
    .section-title {
      font-size: .75rem; text-transform: uppercase; letter-spacing: .04em;
      color: var(--muted); margin: .75rem 0 .35rem;
    }
    .hint { font-size: .85rem; color: var(--muted); margin-bottom: .75rem; line-height: 1.4; text-align: center; }
    .qr-wrap {
      display: flex; justify-content: center; padding: 12px; background: #fff;
      border-radius: 12px; margin-bottom: .5rem; min-height: 268px; align-items: center;
    }
    .qr-wrap img { width: 240px; height: 240px; }
    .pin {
      text-align: center; font-size: 2.4rem; letter-spacing: .28em; font-weight: 700;
      font-variant-numeric: tabular-nums; margin: .35rem 0 .75rem;
    }
    .devices, .log { list-style: none; padding: 0; margin: 0; font-size: .82rem; }
    .devices li, .log li {
      padding: .45rem 0; border-bottom: 1px solid rgba(128,128,128,.15);
      display: flex; justify-content: space-between; align-items: center; gap: .5rem;
    }
    .dev-actions { display: flex; align-items: center; gap: .35rem; flex-shrink: 0; }
    .dev-revoke {
      padding: .2rem .45rem; font-size: .72rem; min-width: auto; flex: none;
      border-radius: 6px; color: var(--err); border-color: rgba(220,38,38,.35);
    }
    .devices li:last-child, .log li:last-child { border-bottom: none; }
    .dev-ok { color: var(--ok); }
    .dev-fail { color: var(--err); }
    .dev-idle { color: var(--muted); }
    .log time { color: var(--muted); white-space: nowrap; font-size: .75rem; }
    .actions { display: flex; gap: .5rem; margin: 1rem 0; flex-wrap: wrap; }
    .pairing-panel[hidden] { display: none; }
    button {
      flex: 1; min-width: 120px; padding: .55rem .9rem; font-size: .9rem;
      border-radius: 8px; border: 1px solid rgba(128,128,128,.35);
      background: transparent; color: inherit; cursor: pointer;
    }
    button:hover { background: rgba(128,128,128,.12); }
    button.primary { background: #2563eb; color: #fff; border-color: #2563eb; }
    button.primary:hover { background: #1d4ed8; }
    .inbox { font-size: .8rem; color: var(--muted); word-break: break-all; text-align: center; margin-top: .5rem; }
    .version { font-size: .78rem; color: var(--muted); }
  </style>
</head>
<body>
  <main>
    <h1>HomeShare</h1>
    <p class="sub">LAN file hub<br><span class="version">v$version</span></p>

    <div class="badge" id="sync-badge">
      <span class="dot ok" id="sync-dot"></span>
      <span id="sync-text">Загрузка…</span>
    </div>

    <div class="stats">
      <div><strong id="stat-devices">0</strong>устройств</div>
      <div><strong id="stat-transfers">0</strong>передач</div>
      <div><strong id="stat-free">—</strong>свободно</div>
    </div>

    <p class="hint" id="pairing-hint">Нажмите «Показать PIN и QR», чтобы привязать новое устройство.</p>
    <div id="pairing-panel" class="pairing-panel" hidden>
      <p class="hint">Отсканируйте QR в HomeShare<br>или введите PIN вручную</p>
      <div class="qr-wrap"><img id="qr" width="240" height="240" alt="QR pairing"></div>
      <div class="pin" id="pin">------</div>
      <div style="text-align:center;font-size:.82rem;color:var(--muted);margin-bottom:.5rem">
        LAN: <strong id="lan-endpoint">—</strong>
      </div>
    </div>

    <div class="section-title">Устройства</div>
    <ul class="devices" id="devices"></ul>
    <div class="actions" id="device-actions" style="margin-top:.35rem;margin-bottom:.75rem;">
      <button type="button" class="dev-revoke" id="revoke-all-btn" onclick="revokeAllDevices()">Отвязать все</button>
    </div>

    <div class="actions">
      <button type="button" class="primary" id="show-pairing-btn" onclick="showPairing()">Показать PIN и QR</button>
      <button type="button" id="refresh-pin-btn" onclick="refreshPin()">Обновить PIN</button>
    </div>

    <div class="section-title">Лог</div>
    <ul class="log" id="log"></ul>
    <p class="inbox" id="inbox-path"></p>
  </main>
  <script>
    function fmtTime(iso) {
      if (!iso) return '-';
      try { return new Date(iso).toLocaleString('ru-RU', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' }); }
      catch (_) { return iso; }
    }
    function fmtBytes(n) {
      if (n == null) return '—';
      const u = ['B','KB','MB','GB','TB'];
      let i = 0; let v = Number(n);
      while (v >= 1024 && i < u.length-1) { v /= 1024; i++; }
      return v.toFixed(i === 0 ? 0 : 1) + u[i];
    }
    function escapeHtml(s) {
      return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }
    function renderDevices(list) {
      const el = document.getElementById('devices');
      const actions = document.getElementById('device-actions');
      if (!list || !list.length) {
        el.innerHTML = '<li><span class="dev-idle">Пока нет — привяжите через QR</span></li>';
        if (actions) actions.style.display = 'none';
        return;
      }
      if (actions) actions.style.display = '';
      el.innerHTML = list.map(d =>
        '<li><span>' + escapeHtml(d.name) + '</span><span class="dev-actions">' +
        '<span class="dev-idle">' + escapeHtml(d.host || '-') + '</span>' +
        '<button type="button" class="dev-revoke" onclick="revokeDevice(' +
        JSON.stringify(d.peer_id) + ',' + JSON.stringify(d.name) + ')">Отвязать</button>' +
        '</span></li>'
      ).join('');
    }
    function renderLog(events) {
      const el = document.getElementById('log');
      if (!events || !events.length) {
        el.innerHTML = '<li><span class="dev-idle">Событий пока нет</span></li>';
        return;
      }
      el.innerHTML = events.slice(0, 12).map(e =>
        '<li><span>' + escapeHtml(e.message) + '</span><time>' + fmtTime(e.at) + '</time></li>'
      ).join('');
    }
    function pairingVisible() {
      const panel = document.getElementById('pairing-panel');
      return panel && !panel.hidden;
    }
    function showPairing() {
      document.getElementById('pairing-panel').hidden = false;
      document.getElementById('pairing-hint').hidden = true;
      document.getElementById('show-pairing-btn').hidden = true;
      refreshStatus();
    }
    function applyStatus(s) {
      if ((s.trusted_count ?? 0) === 0 && !pairingVisible()) showPairing();
      if (pairingVisible()) {
        if (s.pin) document.getElementById('pin').textContent = s.pin;
        const img = document.getElementById('qr');
        if (img && s.pin) {
          img.src = '/hub/qr.svg?pin=' + encodeURIComponent(s.pin) + '&t=' + Date.now();
        }
        if (s.lan_host && s.http_port) {
          document.getElementById('lan-endpoint').textContent = s.lan_host + ':' + s.http_port;
        }
      }
      document.getElementById('stat-devices').textContent = s.trusted_count ?? 0;
      document.getElementById('stat-transfers').textContent = s.active_transfers ?? 0;
      document.getElementById('stat-free').textContent = fmtBytes(s.inbox_free_bytes);
      const dot = document.getElementById('sync-dot');
      dot.className = 'dot ' + (s.sync_badge_kind || 'idle');
      document.getElementById('sync-text').textContent = s.sync_badge_text || '-';
      renderDevices(s.trusted_devices);
      renderLog(s.recent_events);
      document.getElementById('inbox-path').textContent =
        'Inbox (только через config.json): ' + (s.inbox_path || '');
    }
    async function refreshStatus() {
      const r = await fetch('/hub/status');
      applyStatus(await r.json());
    }
    async function refreshPin() {
      await fetch('/hub/pairing/refresh', { method: 'POST' });
      showPairing();
      await refreshStatus();
    }
    async function revokeDevice(peerId, name) {
      if (!confirm('Отвязать устройство «' + name + '»?')) return;
      const r = await fetch('/hub/devices/' + encodeURIComponent(peerId) + '/revoke', { method: 'POST' });
      if (r.ok) applyStatus(await r.json());
    }
    async function revokeAllDevices() {
      if (!confirm('Отвязать все устройства?')) return;
      const r = await fetch('/hub/devices/revoke-all', { method: 'POST' });
      if (r.ok) {
        const body = await r.json();
        if (body.status) applyStatus(body.status);
      }
    }
    setInterval(refreshStatus, 10000);
    refreshStatus();
  </script>
</body>
</html>
''';
}
