import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:homeshare_core/homeshare_core.dart';

import '../protocol/constants.dart';

/// Lightweight UDP beacon for LAN discovery (complements mDNS).
class UdpBeacon {
  UdpBeacon({
    required this.identity,
    required this.port,
    this.p2pPort = HomeShareProtocol.p2pPort,
    this.advertisedHost,
    this.onSendError,
  });

  DeviceIdentity identity;
  final int port;
  final int p2pPort;

  /// Preferred LAN IP to put in beacon payload (and bind announce when possible).
  String? advertisedHost;

  /// Optional logger for announce failures (diagnostics).
  void Function(String message)? onSendError;

  RawDatagramSocket? _socket;
  RawDatagramSocket? _announceSocket;
  Timer? _announceTimer;
  final _peers = <String, DiscoveredPeer>{};
  final _controller = StreamController<List<DiscoveredPeer>>.broadcast();

  Stream<List<DiscoveredPeer>> get peers => _controller.stream;

  List<DiscoveredPeer> get currentPeers => _peers.values.toList();

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket!.broadcastEnabled = true;
    _socket!.listen(_onDatagram);
    await _rebindAnnounceSocket();
    _announceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(announce());
    });
    await announce();
  }

  Future<void> setAdvertisedHost(String? host) async {
    advertisedHost = host;
    await _rebindAnnounceSocket();
    await announce();
  }

  Future<void> _rebindAnnounceSocket() async {
    _announceSocket?.close();
    _announceSocket = null;
    final host = advertisedHost?.trim();
    if (host == null || host.isEmpty) return;
    try {
      final addr = InternetAddress(host);
      if (addr.type != InternetAddressType.IPv4) return;
      _announceSocket = await RawDatagramSocket.bind(addr, 0);
      _announceSocket!.broadcastEnabled = true;
    } catch (e) {
      _announceSocket = null;
      onSendError?.call('announce bind failed on $host: $e');
    }
  }

  Future<void> announce() async {
    final listen = _socket;
    if (listen == null) return;
    final host = advertisedHost ?? await LanAddress.pick();
    final payload = utf8.encode(
      jsonEncode({
        'v': HomeShareProtocol.version,
        'peer_id': identity.peerId,
        'display_name': identity.displayName,
        'port': p2pPort,
        if (host != null) 'host': host,
      }),
    );
    final senders = <RawDatagramSocket>[
      if (_announceSocket != null) _announceSocket!,
      listen,
    ];
    final targets = await LanAddress.broadcastTargets(preferredHost: host);
    for (final socket in senders) {
      for (final target in targets) {
        try {
          socket.send(payload, target, port);
        } catch (e) {
          onSendError?.call('broadcast to ${target.address}:$port failed: $e');
        }
      }
    }
  }

  void _onDatagram(RawSocketEvent event) {
    final socket = _socket;
    if (socket == null || event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    try {
      final map = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      final peerId = map['peer_id'] as String?;
      if (peerId == null || peerId == identity.peerId) return;

      final advertised = map['host'] as String?;
      final source = dg.address.address;
      final host = _pickPeerHost(advertised: advertised, source: source);

      final peer = DiscoveredPeer(
        peerId: PeerId(peerId),
        displayName: map['display_name'] as String? ?? peerId,
        host: host,
        port: (map['port'] as num?)?.toInt() ?? HomeShareProtocol.p2pPort,
        lastSeen: DateTime.now().toUtc(),
      );
      _peers[peerId] = peer;
      _controller.add(currentPeers);
    } catch (e, st) {
      HsLog.p2p.fine('Ignoring invalid beacon datagram', e, st);
    }
  }

  /// Prefer peer-advertised private LAN IP over the UDP source address.
  static String _pickPeerHost({String? advertised, required String source}) {
    final adv = advertised?.trim();
    if (adv != null &&
        adv.isNotEmpty &&
        LanAddress.isPrivateRfc1918(adv) &&
        LanAddress.scoreAddress(adv, 'peer') > 0) {
      return adv;
    }
    if (adv != null &&
        adv.isNotEmpty &&
        LanAddress.scoreAddress(adv, 'peer') >
            LanAddress.scoreAddress(source, 'peer')) {
      return adv;
    }
    return source;
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceSocket?.close();
    _announceSocket = null;
    _socket?.close();
    _socket = null;
    await _controller.close();
  }
}
