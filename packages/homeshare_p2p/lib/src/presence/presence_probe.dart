import 'dart:async';
import 'dart:convert';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:http/http.dart' as http;

import '../protocol/constants.dart';

/// Result of probing a peer's `/health` endpoint.
class PeerHealth {
  const PeerHealth({
    required this.peerId,
    required this.displayName,
    this.version,
  });

  final String peerId;
  final String displayName;
  final String? version;
}

/// TCP presence probe — works when UDP discovery is one-way.
class PresenceProbe {
  PresenceProbe({
    http.Client? client,
    this.timeout = const Duration(seconds: 3),
    this.staleAfter = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  final Duration staleAfter;

  Future<PeerHealth?> probe({
    required String host,
    required int port,
  }) async {
    try {
      final uri = Uri.parse(
        'http://$host:$port${HomeShareProtocol.pathPrefix}/health',
      );
      final res = await _client.get(uri).timeout(timeout);
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final peerId = map['peer_id'] as String?;
      if (peerId == null || peerId.isEmpty) return null;
      return PeerHealth(
        peerId: peerId,
        displayName: map['display_name'] as String? ?? peerId,
        version: map['version'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Apply probe / staleness rules to a trusted peer snapshot.
  TrustedPeer apply({
    required TrustedPeer peer,
    required PeerHealth? health,
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now().toUtc();
    if (health != null && health.peerId == peer.peerId.value) {
      return peer.copyWith(
        displayName: health.displayName,
        online: true,
        lastSeen: ts,
      );
    }
    final last = peer.lastSeen;
    final stale = last == null || ts.difference(last) > staleAfter;
    if (stale) {
      return peer.copyWith(online: false);
    }
    return peer;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
