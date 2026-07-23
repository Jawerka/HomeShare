import 'dart:convert';
import 'dart:io';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:homeshare_p2p/homeshare_p2p.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:homeshare_server/src/event_log.dart';
import 'package:homeshare_server/src/qr_svg.dart';
import 'package:homeshare_server/src/web_ui.dart';

Future<void> main(List<String> args) async {
  HsLog.setup();

  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(
      'HomeShare hub\n\n'
      'Usage:\n'
      '  homeshare-hub [--config path]\n'
      '  homeshare-hub send --to <peer> [--config path] <files...>\n',
    );
    return;
  }

  if (args.isNotEmpty && args.first == 'send') {
    await _handleSend(args.skip(1).toList());
    return;
  }

  String? configPath;
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--config' || args[i] == '-c') && i + 1 < args.length) {
      configPath = args[++i];
    }
  }
  await _runHub(configPath ?? _defaultConfigPath());
}

String _defaultConfigPath() {
  if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'] ?? '.';
    return p.join(home, '.homeshare', 'config.json');
  }
  final etc = File('/etc/homeshare/config.json');
  if (etc.existsSync()) return etc.path;
  final home = Platform.environment['HOME'] ?? '/var/lib/homeshare';
  return p.join(home, '.config', 'homeshare', 'config.json');
}

Future<void> _handleSend(List<String> args) async {
  String? to;
  String? configPath;
  final files = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--to' && i + 1 < args.length) {
      to = args[++i];
    } else if ((args[i] == '--config' || args[i] == '-c') &&
        i + 1 < args.length) {
      configPath = args[++i];
    } else {
      files.add(args[i]);
    }
  }
  if (to == null || files.isEmpty) {
    stderr.writeln('Usage: homeshare-hub send --to <peer> <files...>');
    exitCode = 64;
    return;
  }
  configPath ??= _defaultConfigPath();
  final config = await AppConfig.load(File(configPath));
  final dataDir = Directory(config.dataDir);
  final identity = await DeviceIdentity.loadOrCreate(
    dataDir: dataDir,
    displayName: config.displayName,
  );
  final tokens = await TokenStore.open(dataDir);
  TrustedPeer? peer;
  for (final candidate in config.trustedPeers) {
    if (candidate.peerId.value == to || candidate.displayName == to) {
      peer = candidate;
      break;
    }
  }
  if (peer == null || peer.host == null) {
    stderr.writeln('Peer not found or host unknown: $to');
    exitCode = 1;
    return;
  }
  final client = TransferClient(identity: identity, tokenStore: tokens);
  for (final f in files) {
    final entity = FileSystemEntity.typeSync(f);
    final id = 'cli-${DateTime.now().millisecondsSinceEpoch}';
    if (entity == FileSystemEntityType.directory) {
      await client.sendDirectory(
        peer: peer,
        transferId: id,
        directory: Directory(f),
        onProgress: (t, total) {
          final pct = total == 0 ? 0 : ((t * 100) / total).floor();
          stdout.write('\rSending $f  $pct%');
        },
      );
    } else {
      await client.sendFile(
        peer: peer,
        transferId: id,
        file: File(f),
        onProgress: (t, total) {
          final pct = total == 0 ? 0 : ((t * 100) / total).floor();
          stdout.write('\rSending $f  $pct%');
        },
      );
    }
    stdout.writeln('\nDone: $f');
  }
  client.close();
}

Future<void> _runHub(String configPath) async {
  final configFile = File(configPath);
  final config = await AppConfig.load(
    configFile,
    defaults: AppConfig(
      displayName: 'HomeShare-Linux',
      inboxDir: Platform.isWindows
          ? p.join(Directory.systemTemp.path, 'homeshare-inbox')
          : '/var/homeshare/inbox',
      dataDir: Platform.isWindows
          ? p.join(Platform.environment['USERPROFILE'] ?? '.', '.homeshare')
          : '/var/lib/homeshare',
    ),
  );

  await Directory(config.dataDir).create(recursive: true);
  await Directory(config.inboxDir).create(recursive: true);

  final identity = await DeviceIdentity.loadOrCreate(
    dataDir: Directory(config.dataDir),
    displayName: config.displayName,
  );
  final tokens = await TokenStore.open(Directory(config.dataDir));
  final events = EventLog(maxEntries: 50);
  final pairing = PairingService(
    identity: identity,
    config: config,
    tokenStore: tokens,
  );
  pairing.refreshOffer();

  final inboxWriter = InboxWriter(inboxDir: Directory(config.inboxDir));
  final peerServer = PeerServer(
    identity: identity,
    config: config,
    tokenStore: tokens,
    inboxWriter: inboxWriter,
    pairing: pairing,
    onEvent: (kind, message) => events.add(kind, message),
  );
  await peerServer.start(port: config.p2pPort);

  UdpBeacon? beacon;
  try {
    beacon = UdpBeacon(
      identity: identity,
      port: config.discoveryPort,
      p2pPort: config.p2pPort,
      advertisedHost: peerServer.lanHost,
    );
    await beacon.start();
  } catch (e) {
    events.add('warn', 'UDP beacon failed: $e');
  }

  final hub = HubApp(
    config: config,
    identity: identity,
    pairing: pairing,
    peerServer: peerServer,
    events: events,
    tokens: tokens,
  );

  final server = await shelf_io.serve(
    hub.handler,
    InternetAddress.anyIPv4,
    config.webPort,
  );

  events.add(
    'server',
    'Web UI http://${peerServer.lanHost ?? '127.0.0.1'}:${server.port}',
  );
  stdout.writeln(
    'HomeShare hub v$homeShareVersion\n'
    '  Web UI : http://${peerServer.lanHost ?? '0.0.0.0'}:${server.port}\n'
    '  P2P    : ${config.p2pPort}\n'
    '  Inbox  : ${config.inboxDir}',
  );

  await ProcessSignal.sigint.watch().first;
  await beacon?.stop();
  await peerServer.stop();
  await server.close(force: true);
}

class HubApp {
  HubApp({
    required this.config,
    required this.identity,
    required this.pairing,
    required this.peerServer,
    required this.events,
    required this.tokens,
  });

  final AppConfig config;
  final DeviceIdentity identity;
  final PairingService pairing;
  final PeerServer peerServer;
  final EventLog events;
  final TokenStore tokens;

  Handler get handler {
    final router = Router()
      ..get('/', _index)
      ..get('/hub/status', _status)
      ..post('/hub/pairing/refresh', _refreshPin)
      ..get('/hub/qr.svg', _qrSvg)
      ..get('/hub/qr.png', _qrPngAlias)
      ..post('/hub/devices/<id>/revoke', _revoke)
      ..post('/hub/devices/revoke-all', _revokeAll);

    return const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);
  }

  Response _index(Request request) => Response.ok(
        webUiHtml(version: homeShareVersion),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );

  Future<Response> _status(Request request) async {
    final offer = pairing.getOrCreateOffer();
    final space = await DiskSpace.forPath(config.inboxDir);
    final active = peerServer.sessions.values
        .where((s) => s.state == TransferState.transferring)
        .length;
    final body = {
      'pin': offer.pin.value,
      'lan_host': peerServer.lanHost,
      'http_port': config.p2pPort,
      'web_port': config.webPort,
      'inbox_path': config.inboxDir,
      'inbox_free_bytes': space.probeOk ? space.freeBytes : null,
      'inbox_space_probe_ok': space.probeOk,
      'trusted_count': config.trustedPeers.length,
      'active_transfers': active,
      'display_name': identity.displayName,
      'version': homeShareVersion,
      'sync_badge_kind': active > 0 ? 'syncing' : 'ok',
      'sync_badge_text':
          active > 0 ? 'Идёт передача ($active)' : 'Hub готов',
      'trusted_devices': config.trustedPeers
          .map(
            (d) => {
              'peer_id': d.peerId.value,
              'name': d.displayName,
              'online': d.online,
              'host': d.host,
            },
          )
          .toList(),
      'recent_events': events.toJson(),
      'pending_outbox': 0,
    };
    return Response.ok(
      jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _refreshPin(Request request) async {
    pairing.refreshOffer();
    events.add('pairing', 'PIN refreshed');
    return _status(request);
  }

  Response _qrSvg(Request request) {
    final pin = request.url.queryParameters['pin'] ??
        pairing.getOrCreateOffer().pin.value;
    final host = peerServer.lanHost ?? '127.0.0.1';
    final payload = PairingService.buildQrPayload(
      host: host,
      port: config.p2pPort,
      pin: pin,
    );
    final svg = QrSvg.encode(payload);
    return Response.ok(svg, headers: {'content-type': 'image/svg+xml'});
  }

  Response _qrPngAlias(Request request) => _qrSvg(request);

  Future<Response> _revoke(Request request, String id) async {
    await config.revokePeer(id);
    await tokens.remove(id);
    events.add('pairing', 'Revoked device $id');
    return _status(request);
  }

  Future<Response> _revokeAll(Request request) async {
    await config.revokeAllPeers();
    await tokens.clear();
    events.add('pairing', 'Revoked all devices');
    final status = await _status(request);
    return Response.ok(
      jsonEncode({'status': jsonDecode(await status.readAsString())}),
      headers: {'content-type': 'application/json'},
    );
  }
}
