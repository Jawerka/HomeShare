import 'dart:io';

/// A local IPv4 address that can be used for LAN advertising / pairing.
class LanAddressCandidate {
  const LanAddressCandidate({
    required this.address,
    required this.interfaceName,
    required this.score,
  });

  final String address;
  final String interfaceName;
  final int score;

  String get label => '$interfaceName - $address';

  bool get isPrivateRfc1918 => LanAddress.isPrivateRfc1918(address);
}

/// Prefer real home/office LAN addresses over VPN, APIPA, and virtual adapters.
class LanAddress {
  LanAddress._();

  /// Returns ranked candidates (best first). Empty if none found.
  static Future<List<LanAddressCandidate>> listCandidates() async {
    final out = <LanAddressCandidate>[];
    try {
      final ifaces = await NetworkInterface.list(
        includeLinkLocal: true,
        type: InternetAddressType.IPv4,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          final score = scoreAddress(ip, iface.name);
          if (score <= 0) continue;
          out.add(
            LanAddressCandidate(
              address: ip,
              interfaceName: iface.name,
              score: score,
            ),
          );
        }
      }
    } catch (_) {}
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// Pick best LAN host. [preferred] wins if still present on an interface.
  static Future<String?> pick({String? preferred}) async {
    final candidates = await listCandidates();
    if (candidates.isEmpty) return preferred?.trim().isEmpty == false ? preferred : null;

    final pref = preferred?.trim();
    if (pref != null && pref.isNotEmpty) {
      for (final c in candidates) {
        if (c.address == pref) return pref;
      }
      // Keep explicit preference even if temporarily offline (QR / manual pair).
      if (_looksLikeIpv4(pref)) return pref;
    }
    return candidates.first.address;
  }

  /// Higher is better. Return 0 to exclude.
  static int scoreAddress(String ip, String interfaceName) {
    final parts = _parseIpv4(ip);
    if (parts == null) return 0;

    // Link-local APIPA — almost never useful for HomeShare.
    if (parts[0] == 169 && parts[1] == 254) return 0;

    // CGNAT / Tailscale-style ranges — deprioritize.
    final cgnat = parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127;

    var score = 0;
    if (parts[0] == 192 && parts[1] == 168) {
      score = 300; // typical home Wi‑Fi / Ethernet
    } else if (parts[0] == 10) {
      score = 200;
    } else if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) {
      score = 150;
    } else if (cgnat) {
      score = 40;
    } else {
      // Public / other — last resort only
      score = 20;
    }

    final name = interfaceName.toLowerCase();
    if (_virtualNameHints.any((h) => name.contains(h))) {
      score -= 120;
    }
    return score <= 0 ? 0 : score;
  }

  static bool isPrivateRfc1918(String ip) {
    final parts = _parseIpv4(ip);
    if (parts == null) return false;
    if (parts[0] == 10) return true;
    if (parts[0] == 192 && parts[1] == 168) return true;
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return true;
    return false;
  }

  /// Directed broadcast for [ip] given a CIDR [prefixLength] (default by class).
  /// Example: `192.168.88.10` /24 → `192.168.88.255`.
  static String? subnetBroadcast(String ip, {int? prefixLength}) {
    final parts = _parseIpv4(ip);
    if (parts == null) return null;
    final prefix = prefixLength ?? defaultPrefixLength(ip);
    if (prefix < 0 || prefix > 30) return null;

    final ipInt = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
    final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
    final bcast = ipInt | (~mask & 0xffffffff);
    return '${(bcast >> 24) & 0xff}.'
        '${(bcast >> 16) & 0xff}.'
        '${(bcast >> 8) & 0xff}.'
        '${bcast & 0xff}';
  }

  static int defaultPrefixLength(String ip) {
    final parts = _parseIpv4(ip);
    if (parts == null) return 24;
    if (parts[0] == 10) return 24;
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return 24;
    if (parts[0] == 192 && parts[1] == 168) return 24;
    return 24;
  }

  /// Limited broadcast plus subnet broadcasts for current LAN candidates.
  static Future<List<InternetAddress>> broadcastTargets({
    String? preferredHost,
  }) async {
    final targets = <String>{'255.255.255.255'};
    final candidates = await listCandidates();
    for (final c in candidates) {
      if (!c.isPrivateRfc1918) continue;
      final b = subnetBroadcast(c.address);
      if (b != null) targets.add(b);
    }
    final pref = preferredHost?.trim();
    if (pref != null && pref.isNotEmpty) {
      final b = subnetBroadcast(pref);
      if (b != null) targets.add(b);
    }
    return targets.map(InternetAddress.new).toList();
  }

  static bool _looksLikeIpv4(String ip) => _parseIpv4(ip) != null;

  static List<int>? _parseIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
      nums.add(n);
    }
    return nums;
  }

  static const _virtualNameHints = [
    'vethernet',
    'virtualbox',
    'vmware',
    'vbox',
    'hyper-v',
    'docker',
    'wsl',
    'tailscale',
    'zerotier',
    'hamachi',
    'nordlynx',
    'wireguard',
    'tun',
    'tap',
    'wg',
    'vpn',
    'loopback',
  ];
}
