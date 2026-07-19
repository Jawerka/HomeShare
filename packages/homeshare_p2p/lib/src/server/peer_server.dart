import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_headers.dart';
import '../pairing/pairing_service.dart';
import '../protocol/constants.dart';
import '../protocol/errors.dart';
import '../transfer/transfer_session.dart';

typedef EventLogger = void Function(String kind, String message);
typedef ReceiveUpdateCallback = void Function(TransferSession session);

/// HTTP peer server: pairing + auto-accept file transfer.
class PeerServer {
  PeerServer({
    required this.identity,
    required this.config,
    required this.tokenStore,
    required this.inboxWriter,
    required this.pairing,
    this.onEvent,
    this.onReceiveUpdate,
  });

  final DeviceIdentity identity;
  final AppConfig config;
  final TokenStore tokenStore;
  final InboxWriter inboxWriter;
  final PairingService pairing;
  final EventLogger? onEvent;
  final ReceiveUpdateCallback? onReceiveUpdate;

  final Map<String, TransferSession> sessions = {};
  HttpServer? _server;
  String? lanHost;

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;

  late final AuthHeaders _auth =
      AuthHeaders(identity: identity, tokenStore: tokenStore);

  Future<void> start({InternetAddress? address, int? port}) async {
    final router = Router()
      ..get('${HomeShareProtocol.pathPrefix}/health', _health)
      ..get('${HomeShareProtocol.pathPrefix}/pairing/offer', _pairingOffer)
      ..post('${HomeShareProtocol.pathPrefix}/pairing/confirm', _pairingConfirm)
      ..post('${HomeShareProtocol.pathPrefix}/transfer/offer', _transferOffer)
      ..put(
        '${HomeShareProtocol.pathPrefix}/transfer/<id>/blob',
        _transferBlob,
      )
      ..post(
        '${HomeShareProtocol.pathPrefix}/transfer/<id>/finalize',
        _transferFinalize,
      )
      ..get(
        '${HomeShareProtocol.pathPrefix}/transfer/<id>/status',
        _transferStatus,
      );

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(
      handler,
      address ?? InternetAddress.anyIPv4,
      port ?? config.p2pPort,
    );
    await refreshLanHost();
    onEvent?.call('server', 'P2P listening on ${_server!.port}');
  }

  /// Recompute advertised LAN IP from config preference + interface ranking.
  Future<String?> refreshLanHost() async {
    lanHost = await LanAddress.pick(preferred: config.preferredLanHost);
    return lanHost;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Response _health(Request request) => Response.ok(
        jsonEncode({
          'ok': true,
          'peer_id': identity.peerId,
          'display_name': identity.displayName,
          'version': homeShareVersion,
        }),
        headers: {'content-type': 'application/json'},
      );

  Response _pairingOffer(Request request) {
    return Response.ok(
      jsonEncode(pairing.offerJson(lanHost: lanHost)),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _pairingConfirm(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final result = await pairing.confirmAsHost(
        offerId: body['offer_id'] as String,
        pin: body['pin'] as String,
        guestPeerId: body['peer_id'] as String,
        guestDisplayName: body['display_name'] as String? ?? 'Guest',
        guestPublicKey: body['signing_public_key'] as String? ?? '',
        guestHost: _remoteHost(request),
      );
      onEvent?.call(
        'pairing',
        'Paired with ${body['display_name'] ?? body['peer_id']}',
      );
      return Response.ok(
        jsonEncode(result),
        headers: {'content-type': 'application/json'},
      );
    } on HomeShareException catch (e) {
      return Response(
        e.statusCode ?? 400,
        body: jsonEncode({'error': e.code, 'message': e.message}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _transferOffer(Request request) async {
    final auth = _requireAuth(request, 'POST', request.requestedUri.path);
    if (auth != null) return auth;

    final peerId = _peerId(request)!;
    await _touchPeerOnline(peerId, host: _remoteHost(request));
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final transferId = body['transfer_id'] as String;
    final size = (body['size'] as num).toInt();
    final name = body['name'] as String;
    final kind = (body['kind'] as String?) == 'dir'
        ? TransferKind.dir
        : TransferKind.file;
    final sha256 = body['sha256'] as String?;

    if (sessions.containsKey(transferId) &&
        sessions[transferId]!.state == TransferState.completed) {
      return Response(
        409,
        body: jsonEncode({'error': 'conflict'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final space = await DiskSpace.forPath(config.inboxDir);
    if (!space.hasRoomFor(size)) {
      onEvent?.call('error', 'disk_full for $name ($size bytes)');
      return Response(
        507,
        body: jsonEncode({
          'error': 'disk_full',
          'inbox_free_bytes': space.freeBytes,
          'required_bytes': size,
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final manifest = <FileEntry>[];
    final rawManifest = body['manifest'];
    if (rawManifest is List) {
      for (final item in rawManifest) {
        if (item is Map) {
          try {
            final path = PathSanitize.sanitizeRelative(item['path'] as String);
            manifest.add(
              FileEntry(
                path: path,
                size: (item['size'] as num).toInt(),
                sha256: item['sha256'] as String?,
              ),
            );
          } on PathSanitizeException catch (e) {
            return Response(
              400,
              body: jsonEncode({'error': 'path_invalid', 'message': '$e'}),
              headers: {'content-type': 'application/json'},
            );
          }
        }
      }
    }

    await inboxWriter.ensureReady();
    final existing = sessions[transferId];
    final resume = existing?.receivedBytes ??
        await inboxWriter.receivedBytes(transferId);

    final session = TransferSession(
      transferId: transferId,
      fromPeerId: peerId,
      name: name,
      kind: kind,
      totalBytes: size,
      sha256: sha256,
      manifest: manifest,
    )
      ..receivedBytes = resume
      ..state = TransferState.transferring;
    sessions[transferId] = session;
    onReceiveUpdate?.call(session);
    onEvent?.call('transfer', 'Receiving $name ($size bytes)');

    return Response.ok(
      jsonEncode({
        'status': 'ready',
        'resume_offset': resume,
        'inbox_free_bytes': space.freeBytes,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _transferBlob(Request request, String id) async {
    final auth = _requireAuth(request, 'PUT', request.requestedUri.path);
    if (auth != null) return auth;

    final session = sessions[id];
    if (session == null) {
      return Response.notFound(jsonEncode({'error': 'unknown_transfer'}));
    }

    final relativePath =
        request.headers[HomeShareProtocol.headerPath] ?? 'payload';
    try {
      PathSanitize.sanitizeRelative(relativePath);
    } on PathSanitizeException catch (e) {
      return Response(
        400,
        body: jsonEncode({'error': 'path_invalid', 'message': '$e'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final offsetHeader = request.headers[HomeShareProtocol.headerUploadOffset];
    final offset = int.tryParse(offsetHeader ?? '0') ?? 0;

    // Stream to disk — avoid buffering the whole chunk in a List.
    final tmp = await inboxWriter.openWrite(
      transferId: id,
      relativePath: relativePath,
      offset: offset,
    );
    var written = offset;
    try {
      await for (final chunk in request.read()) {
        await tmp.add(chunk);
        written += chunk.length;
      }
      await tmp.close();
    } catch (e) {
      await tmp.abort();
      rethrow;
    }

    session.perFileReceived[relativePath] = written;
    if (session.kind == TransferKind.file) {
      session.receivedBytes = written;
    } else {
      session.receivedBytes =
          session.perFileReceived.values.fold(0, (a, b) => a + b);
    }
    onReceiveUpdate?.call(session);

    return Response.ok(
      jsonEncode({
        'received': session.receivedBytes,
        'status': 'writing',
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _transferFinalize(Request request, String id) async {
    final auth = _requireAuth(request, 'POST', request.requestedUri.path);
    if (auth != null) return auth;

    final session = sessions[id];
    if (session == null) {
      return Response.notFound(jsonEncode({'error': 'unknown_transfer'}));
    }

    try {
      session.state = TransferState.verifying;
      final bodyRaw = await request.readAsString();
      Map<String, dynamic> body = {};
      if (bodyRaw.isNotEmpty) {
        body = jsonDecode(bodyRaw) as Map<String, dynamic>;
      }

      if (session.kind == TransferKind.dir) {
        // Verify each file hash if provided.
        for (final entry in session.manifest) {
          if (entry.sha256 == null) continue;
          final actual = await inboxWriter.hashTemp(
            transferId: id,
            relativePath: entry.path,
          );
          if (actual != entry.sha256) {
            throw Sha256MismatchException(
              expected: entry.sha256!,
              actual: actual,
            );
          }
        }
        final dest = await inboxWriter.finalizeDirToInbox(
          transferId: id,
          desiredName: session.name,
        );
        session.state = TransferState.completed;
        onReceiveUpdate?.call(session);
        onEvent?.call('transfer', 'Saved directory ${dest.path}');
      } else {
        final expected = body['sha256'] as String? ?? session.sha256;
        final dest = await inboxWriter.finalizeToInbox(
          transferId: id,
          desiredName: session.name,
          expectedSha256: expected,
        );
        session.state = TransferState.completed;
        onReceiveUpdate?.call(session);
        onEvent?.call('transfer', 'Saved ${dest.path}');
      }

      return Response.ok(
        jsonEncode({'status': 'completed'}),
        headers: {'content-type': 'application/json'},
      );
    } on Sha256MismatchException catch (e) {
      session.state = TransferState.failed;
      session.error = '$e';
      await inboxWriter.abort(id);
      onReceiveUpdate?.call(session);
      onEvent?.call('error', 'sha256 mismatch for ${session.name}');
      return Response(
        400,
        body: jsonEncode({'error': 'sha256_mismatch', 'message': '$e'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      session.state = TransferState.failed;
      session.error = '$e';
      onReceiveUpdate?.call(session);
      onEvent?.call('error', 'finalize failed: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'finalize_failed', 'message': '$e'}),
      );
    }
  }

  Response _transferStatus(Request request, String id) {
    final session = sessions[id];
    if (session == null) {
      return Response.notFound(jsonEncode({'error': 'unknown_transfer'}));
    }
    return Response.ok(
      jsonEncode(session.statusJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Response? _requireAuth(Request request, String method, String path) {
    final result = _auth.validate(
      headers: request.headers,
      method: method,
      path: path,
      isTrusted: (id) => config.findPeer(id) != null,
    );
    if (!result.ok) {
      return Response(
        result.statusCode,
        body: jsonEncode({
          'error': result.statusCode == 403 ? 'not_trusted' : 'auth_required',
          'message': result.message,
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    return null;
  }

  String? _peerId(Request request) {
    for (final e in request.headers.entries) {
      if (e.key.toLowerCase() == HomeShareProtocol.headerPeerId) {
        return e.value;
      }
    }
    return null;
  }

  String? _remoteHost(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.trim().isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final info = request.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) {
      final addr = info.remoteAddress.address;
      if (addr.isNotEmpty && addr != '127.0.0.1' && addr != '::1') {
        return addr;
      }
      return addr;
    }
    return null;
  }

  Future<void> _touchPeerOnline(String peerId, {String? host}) async {
    final existing = config.findPeer(peerId);
    if (existing == null) return;
    await config.upsertPeer(
      existing.copyWith(
        host: host ?? existing.host,
        online: true,
        lastSeen: DateTime.now().toUtc(),
      ),
    );
  }
}
