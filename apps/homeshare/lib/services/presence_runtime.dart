import 'dart:async';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:homeshare_p2p/homeshare_p2p.dart';

/// Periodic LAN presence probe for trusted peers.
class PresenceRuntime {
  PresenceRuntime({
    required this.config,
    required this.onChanged,
  });

  final AppConfig config;
  final void Function() onChanged;

  PresenceProbe? _probe;
  Timer? _timer;

  void start({Duration interval = const Duration(seconds: 5)}) {
    _probe = PresenceProbe();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      unawaited(probeOnce());
    });
    unawaited(probeOnce());
  }

  Future<void> probeOnce() async {
    final probe = _probe;
    if (probe == null) return;
    var changed = false;
    for (final peer in List<TrustedPeer>.from(config.trustedPeers)) {
      final host = peer.host;
      if (host == null || host.isEmpty) continue;
      final health = await probe.probe(host: host, port: peer.port);
      final updated = probe.apply(peer: peer, health: health);
      if (updated.online != peer.online ||
          updated.displayName != peer.displayName ||
          updated.host != peer.host ||
          updated.lastSeen != peer.lastSeen) {
        await config.upsertPeer(updated);
        changed = true;
      }
    }
    if (changed) onChanged();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _probe?.close();
    _probe = null;
  }
}
