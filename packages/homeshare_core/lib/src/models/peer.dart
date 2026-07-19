/// Stable peer identity used across discovery, trust and transfer.
class PeerId {
  const PeerId(this.value);

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is PeerId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Trusted peer metadata (secrets live in [TokenStore], not here).
class TrustedPeer {
  const TrustedPeer({
    required this.peerId,
    required this.displayName,
    this.alias,
    this.host,
    this.port = 45838,
    this.signingPublicKey,
    this.tlsCertSha256,
    this.lastSeen,
    this.online = false,
  });

  final PeerId peerId;
  final String displayName;

  /// Local nickname; never overwritten by discovery/presence.
  final String? alias;
  final String? host;
  final int port;
  final String? signingPublicKey;
  final String? tlsCertSha256;
  final DateTime? lastSeen;
  final bool online;

  /// Name shown in UI.
  String get label {
    final a = alias?.trim();
    if (a != null && a.isNotEmpty) return a;
    return displayName;
  }

  TrustedPeer copyWith({
    PeerId? peerId,
    String? displayName,
    String? alias,
    bool clearAlias = false,
    String? host,
    int? port,
    String? signingPublicKey,
    String? tlsCertSha256,
    DateTime? lastSeen,
    bool? online,
  }) {
    return TrustedPeer(
      peerId: peerId ?? this.peerId,
      displayName: displayName ?? this.displayName,
      alias: clearAlias ? null : (alias ?? this.alias),
      host: host ?? this.host,
      port: port ?? this.port,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      tlsCertSha256: tlsCertSha256 ?? this.tlsCertSha256,
      lastSeen: lastSeen ?? this.lastSeen,
      online: online ?? this.online,
    );
  }

  Map<String, Object?> toJson() => {
        'peer_id': peerId.value,
        'display_name': displayName,
        if (alias != null && alias!.isNotEmpty) 'alias': alias,
        if (host != null) 'host': host,
        'port': port,
        if (signingPublicKey != null) 'signing_public_key': signingPublicKey,
        if (tlsCertSha256 != null) 'tls_cert_sha256': tlsCertSha256,
        if (lastSeen != null) 'last_seen': lastSeen!.toIso8601String(),
      };

  factory TrustedPeer.fromJson(Map<String, Object?> json) {
    return TrustedPeer(
      peerId: PeerId(json['peer_id']! as String),
      displayName: json['display_name']! as String,
      alias: json['alias'] as String?,
      host: json['host'] as String?,
      port: (json['port'] as num?)?.toInt() ?? 45838,
      signingPublicKey: json['signing_public_key'] as String?,
      tlsCertSha256: json['tls_cert_sha256'] as String?,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen']! as String)
          : null,
    );
  }
}

/// Discovered (not necessarily trusted) LAN neighbour.
class DiscoveredPeer {
  const DiscoveredPeer({
    required this.peerId,
    required this.displayName,
    required this.host,
    required this.port,
    this.lastSeen,
  });

  final PeerId peerId;
  final String displayName;
  final String host;
  final int port;
  final DateTime? lastSeen;
}
