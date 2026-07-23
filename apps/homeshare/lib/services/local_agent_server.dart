import 'dart:convert';
import 'dart:io';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

/// Loopback HTTP agent for Explorer shell extension / single-instance handoff.
class LocalAgentServer {
  LocalAgentServer({
    required this.config,
    required this.sendPaths,
    required this.queuePendingSendPaths,
    this.onRequestShowWindow,
  });

  final AppConfig config;
  final Future<void> Function(List<String> paths, {required String peerId})
      sendPaths;
  final void Function(List<String> paths) queuePendingSendPaths;
  final Future<void> Function()? onRequestShowWindow;

  HttpServer? _server;

  HttpServer? get server => _server;

  Future<void> start() async {
    final router = shelf_router.Router()
      ..get('/v1/health', (_) => Response.ok('{"ok":true}'))
      ..get('/v1/peers/online', (_) {
        final online = config.trustedPeers
            .where((p) => p.online && p.host != null)
            .map(
              (p) => {
                'peer_id': p.peerId.value,
                'display_name': p.label,
                'host': p.host,
                'port': p.port,
              },
            )
            .toList();
        return Response.ok(
          jsonEncode({'peers': online}),
          headers: {'content-type': 'application/json'},
        );
      })
      ..post('/v1/send', (Request request) async {
        final body =
            jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final peerId = body['peer_id'] as String;
        final paths =
            (body['paths'] as List).map((e) => e as String).toList();
        await sendPaths(paths, peerId: peerId);
        return Response.ok(jsonEncode({'ok': true}));
      })
      ..post('/v1/invoke', (Request request) async {
        final body =
            jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final paths = (body['paths'] as List? ?? const [])
            .map((e) => e as String)
            .where((e) => e.isNotEmpty)
            .toList();
        final peerId = body['peer_id'] as String?;
        final show = body['show'] as bool? ?? true;
        if (show) {
          await onRequestShowWindow?.call();
        }
        if (paths.isEmpty) {
          return Response.ok(jsonEncode({'ok': true, 'action': 'show'}));
        }
        if (peerId != null && peerId.isNotEmpty) {
          await sendPaths(paths, peerId: peerId);
          return Response.ok(jsonEncode({'ok': true, 'action': 'send'}));
        }
        queuePendingSendPaths(paths);
        return Response.ok(jsonEncode({'ok': true, 'action': 'picker'}));
      });

    try {
      _server = await shelf_io.serve(
        router.call,
        InternetAddress.loopbackIPv4,
        config.agentPort,
      );
    } on SocketException catch (e) {
      throw StateError(
        'Agent port ${config.agentPort} busy (another HomeShare?). $e',
      );
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
