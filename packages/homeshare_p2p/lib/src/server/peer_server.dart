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
import '../protocol/http_helpers.dart';
import '../transfer/transfer_handlers.dart';
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
    Future<DiskSpaceReport> Function(String path)? diskSpaceForPath,
  }) : diskSpaceForPath = diskSpaceForPath ?? DiskSpace.forPath;

  final DeviceIdentity identity;
  final AppConfig config;
  final TokenStore tokenStore;
  final InboxWriter inboxWriter;
  final PairingService pairing;
  final EventLogger? onEvent;
  final ReceiveUpdateCallback? onReceiveUpdate;
  final Future<DiskSpaceReport> Function(String path) diskSpaceForPath;

  final Map<String, TransferSession> sessions = {};
  HttpServer? _server;
  String? lanHost;
  late final TransferHandlers _transfers;

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;

  late final AuthHeaders _auth =
      AuthHeaders(identity: identity, tokenStore: tokenStore);

  Future<void> start({InternetAddress? address, int? port}) async {
    _transfers = TransferHandlers(
      config: config,
      inboxWriter: inboxWriter,
      sessions: sessions,
      requireAuth: _requireAuth,
      peerIdFrom: _peerId,
      remoteHost: _remoteHost,
      touchPeerOnline: _touchPeerOnline,
      diskSpaceForPath: diskSpaceForPath,
      onEvent: onEvent,
      onReceiveUpdate: onReceiveUpdate,
    );

    final router = Router()
      ..get('${HomeShareProtocol.pathPrefix}/health', _health)
      ..get('${HomeShareProtocol.pathPrefix}/pairing/offer', _pairingOffer)
      ..post('${HomeShareProtocol.pathPrefix}/pairing/confirm', _pairingConfirm)
      ..post('${HomeShareProtocol.pathPrefix}/transfer/offer', _transfers.offer)
      ..put(
        '${HomeShareProtocol.pathPrefix}/transfer/<id>/blob',
        _transfers.blob,
      )
      ..post(
        '${HomeShareProtocol.pathPrefix}/transfer/<id>/finalize',
        _transfers.finalize,
      )
      ..get(
        '${HomeShareProtocol.pathPrefix}/transfer/<id>/status',
        _transfers.status,
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

  Response _health(Request request) => jsonOk({
        'ok': true,
        'peer_id': identity.peerId,
        'display_name': identity.displayName,
        'version': homeShareVersion,
      });

  Response _pairingOffer(Request request) =>
      jsonOk(pairing.offerJson(lanHost: lanHost));

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
      return jsonOk(result);
    } on HomeShareException catch (e) {
      return jsonError(e.code, e.message, status: e.statusCode ?? 400);
    }
  }

  Response? _requireAuth(Request request, String method, String path) {
    final result = _auth.validate(
      headers: request.headers,
      method: method,
      path: path,
      isTrusted: (id) => config.findPeer(id) != null,
    );
    if (!result.ok) {
      return jsonError(
        result.statusCode == 403 ? 'not_trusted' : 'auth_required',
        result.message ?? 'auth failed',
        status: result.statusCode,
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
