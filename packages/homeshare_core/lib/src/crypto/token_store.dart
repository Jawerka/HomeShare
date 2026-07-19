import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Stores auth tokens separately from public trusted-peer metadata.
class TokenStore {
  TokenStore(this._file);

  final File _file;
  final Map<String, String> _tokens = {};

  static Future<TokenStore> open(Directory dataDir) async {
    await dataDir.create(recursive: true);
    final file = File('${dataDir.path}${Platform.pathSeparator}tokens.json');
    final store = TokenStore(file);
    await store._load();
    return store;
  }

  Future<void> _load() async {
    if (!await _file.exists()) return;
    final map = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    _tokens
      ..clear()
      ..addAll(map.map((k, v) => MapEntry(k, v as String)));
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_tokens),
    );
  }

  String? get(String peerId) => _tokens[peerId];

  Future<void> put(String peerId, String token) async {
    _tokens[peerId] = token;
    await _save();
  }

  Future<void> remove(String peerId) async {
    _tokens.remove(peerId);
    await _save();
  }

  Future<void> clear() async {
    _tokens.clear();
    await _save();
  }

  static String generateToken({Random? random}) {
    final r = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
