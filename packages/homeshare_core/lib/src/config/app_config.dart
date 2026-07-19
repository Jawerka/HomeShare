import 'dart:convert';
import 'dart:io';

import '../models/peer.dart';

/// Application configuration shared by clients and Linux hub.
class AppConfig {
  AppConfig({
    required this.displayName,
    required this.inboxDir,
    required this.dataDir,
    this.webPort = 8787,
    this.p2pPort = 45838,
    this.discoveryPort = 45837,
    this.agentPort = 47831,
    this.preferredLanHost,
    this.backgroundPresenceEnabled = true,
    this.backgroundPresenceMinutes = 3,
    List<TrustedPeer>? trustedPeers,
  }) : trustedPeers = trustedPeers ?? [];

  String displayName;
  String inboxDir;
  String dataDir;
  int webPort;
  int p2pPort;
  int discoveryPort;
  int agentPort;

  /// Explicit LAN IPv4 for QR / pairing / discovery advertise.
  /// `null` or empty = auto-pick (prefer 192.168.x.x).
  String? preferredLanHost;

  /// Android: keep a quiet FGS so the phone stays receivable.
  bool backgroundPresenceEnabled;

  /// How often to re-announce on the LAN while background presence is on.
  int backgroundPresenceMinutes;
  List<TrustedPeer> trustedPeers;

  static const defaultP2pPort = 45838;
  static const defaultDiscoveryPort = 45837;
  static const defaultWebPort = 8787;
  static const defaultAgentPort = 47831;

  File get _peersFile =>
      File('$dataDir${Platform.pathSeparator}trusted_peers.json');

  Map<String, Object?> toJson() => {
        'display_name': displayName,
        'inbox_dir': inboxDir,
        'data_dir': dataDir,
        'web_port': webPort,
        'p2p_port': p2pPort,
        'discovery_port': discoveryPort,
        'agent_port': agentPort,
        if (preferredLanHost != null && preferredLanHost!.trim().isNotEmpty)
          'preferred_lan_host': preferredLanHost!.trim(),
        'background_presence_enabled': backgroundPresenceEnabled,
        'background_presence_minutes': backgroundPresenceMinutes,
      };

  factory AppConfig.fromJson(Map<String, Object?> json) {
    final preferred = json['preferred_lan_host'] as String?;
    return AppConfig(
      displayName: json['display_name'] as String? ?? 'HomeShare',
      inboxDir: json['inbox_dir'] as String? ??
          '${Directory.systemTemp.path}${Platform.pathSeparator}homeshare-inbox',
      dataDir: json['data_dir'] as String? ??
          '${Directory.systemTemp.path}${Platform.pathSeparator}homeshare-data',
      webPort: (json['web_port'] as num?)?.toInt() ?? defaultWebPort,
      p2pPort: (json['p2p_port'] as num?)?.toInt() ?? defaultP2pPort,
      discoveryPort:
          (json['discovery_port'] as num?)?.toInt() ?? defaultDiscoveryPort,
      agentPort: (json['agent_port'] as num?)?.toInt() ?? defaultAgentPort,
      preferredLanHost:
          (preferred != null && preferred.trim().isNotEmpty) ? preferred.trim() : null,
      backgroundPresenceEnabled:
          json['background_presence_enabled'] as bool? ?? true,
      backgroundPresenceMinutes:
          (json['background_presence_minutes'] as num?)?.toInt() ?? 3,
    );
  }

  static Future<AppConfig> load(File file, {AppConfig? defaults}) async {
    final fallback = defaults ??
        AppConfig(
          displayName: 'HomeShare',
          inboxDir:
              '${Directory.systemTemp.path}${Platform.pathSeparator}homeshare-inbox',
          dataDir:
              '${Directory.systemTemp.path}${Platform.pathSeparator}homeshare-data',
        );
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(fallback.toJson()),
      );
      await fallback.loadTrustedPeers();
      return fallback;
    }
    final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final config = AppConfig.fromJson(Map<String, Object?>.from(map));
    await config.loadTrustedPeers();
    return config;
  }

  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  Future<void> loadTrustedPeers() async {
    final file = _peersFile;
    if (!await file.exists()) {
      trustedPeers = [];
      return;
    }
    final raw = jsonDecode(await file.readAsString());
    if (raw is! List) {
      trustedPeers = [];
      return;
    }
    trustedPeers = raw
        .whereType<Map>()
        .map((e) => TrustedPeer.fromJson(Map<String, Object?>.from(e)))
        .toList();
  }

  Future<void> saveTrustedPeers() async {
    await Directory(dataDir).create(recursive: true);
    await _peersFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        trustedPeers.map((e) => e.toJson()).toList(),
      ),
    );
  }

  TrustedPeer? findPeer(String peerId) {
    for (final p in trustedPeers) {
      if (p.peerId.value == peerId) return p;
    }
    return null;
  }

  Future<void> upsertPeer(TrustedPeer peer) async {
    trustedPeers.removeWhere((p) => p.peerId == peer.peerId);
    trustedPeers.add(peer);
    await saveTrustedPeers();
  }

  Future<void> revokePeer(String peerId) async {
    trustedPeers.removeWhere((p) => p.peerId.value == peerId);
    await saveTrustedPeers();
  }

  Future<void> revokeAllPeers() async {
    trustedPeers.clear();
    await saveTrustedPeers();
  }
}
