import 'dart:convert';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:homeshare_p2p/homeshare_p2p.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('PresenceProbe.apply marks online and updates display name', () {
    final probe = PresenceProbe(staleAfter: const Duration(seconds: 15));
    final peer = TrustedPeer(
      peerId: const PeerId('abc'),
      displayName: 'Old',
      host: '192.168.1.2',
      online: false,
      lastSeen: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );
    final updated = probe.apply(
      peer: peer,
      health: const PeerHealth(peerId: 'abc', displayName: 'NewPC'),
      now: DateTime.now().toUtc(),
    );
    expect(updated.online, isTrue);
    expect(updated.displayName, 'NewPC');
  });

  test('PresenceProbe.apply marks offline when stale and probe fails', () {
    final probe = PresenceProbe(staleAfter: const Duration(seconds: 15));
    final peer = TrustedPeer(
      peerId: const PeerId('abc'),
      displayName: 'PC',
      host: '192.168.1.2',
      online: true,
      lastSeen: DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
    );
    final updated = probe.apply(
      peer: peer,
      health: null,
      now: DateTime.now().toUtc(),
    );
    expect(updated.online, isFalse);
  });

  test('PresenceProbe.apply keeps online when recently seen and probe fails', () {
    final probe = PresenceProbe(staleAfter: const Duration(seconds: 15));
    final now = DateTime.now().toUtc();
    final peer = TrustedPeer(
      peerId: const PeerId('abc'),
      displayName: 'PC',
      host: '192.168.1.2',
      online: true,
      lastSeen: now.subtract(const Duration(seconds: 5)),
    );
    final updated = probe.apply(peer: peer, health: null, now: now);
    expect(updated.online, isTrue);
  });

  test('PresenceProbe.probe parses health JSON', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/homeshare/p2p/health');
      return http.Response(
        jsonEncode({
          'ok': true,
          'peer_id': 'peer-1',
          'display_name': 'Phone',
          'version': '0.1.0',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final probe = PresenceProbe(client: client);
    final health = await probe.probe(host: '127.0.0.1', port: 9);
    expect(health?.peerId, 'peer-1');
    expect(health?.displayName, 'Phone');
    probe.close();
  });

  test('QR payload uses real host', () {
    expect(
      PairingService.buildQrPayload(
        host: '192.168.1.5',
        port: 45838,
        pin: '123456',
      ),
      'homeshare://pair?host=192.168.1.5&port=45838&pin=123456',
    );
  });
}
