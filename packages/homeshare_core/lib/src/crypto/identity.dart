import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Local device identity (peer id + signing key material).
class DeviceIdentity {
  DeviceIdentity({
    required this.peerId,
    required this.displayName,
    required this.seed,
  });

  final String peerId;
  String displayName;

  /// 32-byte seed used to derive HMAC signatures (Ed25519-compatible placeholder).
  final Uint8List seed;

  /// Public key material derived from seed (hex).
  String get publicKeyHex => sha256.convert(seed).toString();

  Map<String, Object?> toPublicJson() => {
        'peer_id': peerId,
        'display_name': displayName,
        'signing_public_key': publicKeyHex,
      };

  /// Sign canonical payload with HMAC-SHA256 over seed (portable stand-in for Ed25519).
  String sign(String canonicalPayload) {
    final hmac = Hmac(sha256, seed);
    return hmac.convert(utf8.encode(canonicalPayload)).toString();
  }

  bool verify(String canonicalPayload, String signatureHex, String publicKeyHex) {
    if (publicKeyHex != this.publicKeyHex) return false;
    return sign(canonicalPayload) == signatureHex;
  }

  Future<void> persist(Directory dataDir) async {
    await dataDir.create(recursive: true);
    final file = File('${dataDir.path}${Platform.pathSeparator}identity.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'peer_id': peerId,
        'display_name': displayName,
        'seed': _hexEncode(seed),
      }),
    );
  }

  /// Update local display name and rewrite identity.json.
  Future<void> updateDisplayName(String name, {required Directory dataDir}) async {
    displayName = name.trim().isEmpty ? displayName : name.trim();
    await persist(dataDir);
  }

  static Future<DeviceIdentity> loadOrCreate({
    required Directory dataDir,
    required String displayName,
  }) async {
    await dataDir.create(recursive: true);
    final file = File('${dataDir.path}${Platform.pathSeparator}identity.json');
    if (await file.exists()) {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final seedHex = map['seed'] as String;
      return DeviceIdentity(
        peerId: map['peer_id'] as String,
        displayName: map['display_name'] as String? ?? displayName,
        seed: Uint8List.fromList(_hexDecode(seedHex)),
      );
    }
    final random = Random.secure();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final peerId = _uuidV4(random);
    final identity = DeviceIdentity(
      peerId: peerId,
      displayName: displayName,
      seed: seed,
    );
    await identity.persist(dataDir);
    return identity;
  }

  static String _uuidV4(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = _hexEncode(bytes);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

String _hexEncode(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

List<int> _hexDecode(String hex) {
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}
