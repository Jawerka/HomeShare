import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../protocol/constants.dart';
import '../protocol/errors.dart';

/// Host-side pairing session (one guest at a time).
class PairingOffer {
  PairingOffer({
    required this.offerId,
    required this.pin,
    required this.createdAt,
  });

  final String offerId;
  final PairingPin pin;
  final DateTime createdAt;

  bool get isExpired => pin.isExpired;
}

/// Pairing service: create offer (host) or confirm as guest.
class PairingService {
  PairingService({
    required this.identity,
    required this.config,
    required this.tokenStore,
  });

  final DeviceIdentity identity;
  final AppConfig config;
  final TokenStore tokenStore;

  PairingOffer? _active;
  final _uuid = const Uuid();

  PairingOffer refreshOffer() {
    _active = PairingOffer(
      offerId: _uuid.v4(),
      pin: PairingPin.generate(),
      createdAt: DateTime.now().toUtc(),
    );
    return _active!;
  }

  PairingOffer getOrCreateOffer() {
    final active = _active;
    if (active == null || active.isExpired) {
      return refreshOffer();
    }
    return active;
  }

  Map<String, Object?> offerJson({String? lanHost}) {
    final offer = getOrCreateOffer();
    final host = (lanHost != null && lanHost.trim().isNotEmpty)
        ? lanHost.trim()
        : null;
    return {
      'offer_id': offer.offerId,
      'pin': offer.pin.value,
      'display_name': identity.displayName,
      'peer_id': identity.peerId,
      'http_port': config.p2pPort,
      if (host != null) 'lan_host': host,
      'qr': host == null
          ? null
          : buildQrPayload(
              host: host,
              port: config.p2pPort,
              pin: offer.pin.value,
            ),
    };
  }

  static String buildQrPayload({
    required String host,
    required int port,
    required String pin,
  }) {
    return 'homeshare://pair?host=$host&port=$port&pin=$pin';
  }

  /// Host confirms guest after PIN check.
  Future<Map<String, Object?>> confirmAsHost({
    required String offerId,
    required String pin,
    required String guestPeerId,
    required String guestDisplayName,
    required String guestPublicKey,
    String? guestHost,
    int? guestPort,
  }) async {
    final active = _active;
    if (active == null || active.offerId != offerId) {
      throw HomeShareException('pairing', 'no active offer', statusCode: 400);
    }
    if (active.isExpired) {
      throw HomeShareException('pairing', 'offer expired', statusCode: 400);
    }
    if (active.pin.value != pin) {
      throw HomeShareException('pairing', 'bad pin', statusCode: 403);
    }

    final token = TokenStore.generateToken();
    await tokenStore.put(guestPeerId, token);
    await config.upsertPeer(
      TrustedPeer(
        peerId: PeerId(guestPeerId),
        displayName: guestDisplayName,
        host: guestHost,
        port: guestPort ?? HomeShareProtocol.p2pPort,
        signingPublicKey: guestPublicKey,
        lastSeen: DateTime.now().toUtc(),
        online: guestHost != null && guestHost.isNotEmpty,
      ),
    );
    // Consume offer — one guest per session.
    _active = null;

    return {
      'auth_token': token,
      'peer_id': identity.peerId,
      'display_name': identity.displayName,
      'signing_public_key': identity.publicKeyHex,
      'http_port': config.p2pPort,
    };
  }

  /// Guest joins host by PIN.
  Future<TrustedPeer> confirmAsGuest({
    required String host,
    required int port,
    required String pin,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final offerUri =
          Uri.parse('http://$host:$port${HomeShareProtocol.pathPrefix}/pairing/offer');
      final offerRes = await c.get(offerUri);
      if (offerRes.statusCode != 200) {
        throw HomeShareException(
          'pairing',
          'offer failed: ${offerRes.statusCode}',
          statusCode: offerRes.statusCode,
        );
      }
      final offer =
          jsonDecode(offerRes.body) as Map<String, dynamic>;
      if (offer['pin'] != pin) {
        // Host returns current pin in offer for UX; guest must match.
        // Guest sends PIN; host validates before exchanging tokens.
      }
      final confirmUri = Uri.parse(
        'http://$host:$port${HomeShareProtocol.pathPrefix}/pairing/confirm',
      );
      final body = jsonEncode({
        'offer_id': offer['offer_id'],
        'pin': pin,
        'peer_id': identity.peerId,
        'display_name': identity.displayName,
        'signing_public_key': identity.publicKeyHex,
      });
      final confirmRes = await c.post(
        confirmUri,
        headers: {'content-type': 'application/json'},
        body: body,
      );
      if (confirmRes.statusCode != 200) {
        throw HomeShareException(
          'pairing',
          'confirm failed: ${confirmRes.body}',
          statusCode: confirmRes.statusCode,
        );
      }
      final result = jsonDecode(confirmRes.body) as Map<String, dynamic>;
      final hostPeerId = result['peer_id'] as String;
      final token = result['auth_token'] as String;
      await tokenStore.put(hostPeerId, token);
      final peer = TrustedPeer(
        peerId: PeerId(hostPeerId),
        displayName: result['display_name'] as String? ?? hostPeerId,
        host: host,
        port: (result['http_port'] as num?)?.toInt() ?? port,
        signingPublicKey: result['signing_public_key'] as String?,
        lastSeen: DateTime.now().toUtc(),
        online: true,
      );
      await config.upsertPeer(peer);
      return peer;
    } finally {
      if (client == null) c.close();
    }
  }
}

/// Simple QR SVG helper for hub pairing payload.
/// Real PNG is produced in the server layer; this builds the pairing URI.
String pairingUriFor({
  required String host,
  required int port,
  required String pin,
}) =>
    PairingService.buildQrPayload(host: host, port: port, pin: pin);

/// Deterministic fake for tests.
String testPin([int seed = 42]) {
  final r = Random(seed);
  return r.nextInt(1000000).toString().padLeft(6, '0');
}
