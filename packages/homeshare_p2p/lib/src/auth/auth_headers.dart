import 'package:homeshare_core/homeshare_core.dart';

import '../protocol/constants.dart';

/// Builds and validates HomeShare auth headers.
class AuthHeaders {
  AuthHeaders({
    required this.identity,
    required this.tokenStore,
  });

  final DeviceIdentity identity;
  final TokenStore tokenStore;

  Map<String, String> forRequest({
    required String peerId,
    required String method,
    required String path,
    bool sign = true,
  }) {
    final token = tokenStore.get(peerId);
    final headers = <String, String>{
      HomeShareProtocol.headerPeerId: identity.peerId,
      if (token != null) HomeShareProtocol.headerAuthToken: token,
    };
    if (sign) {
      final ts = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
      final canonical = '$method\n$path\n$ts\n${identity.peerId}';
      headers[HomeShareProtocol.headerTimestamp] = ts;
      headers[HomeShareProtocol.headerSignature] = identity.sign(canonical);
    }
    return headers;
  }

  /// Validate incoming request from a trusted peer.
  AuthResult validate({
    required Map<String, String> headers,
    required String method,
    required String path,
    required bool Function(String peerId) isTrusted,
    String? expectedToken,
  }) {
    final peerId = _header(headers, HomeShareProtocol.headerPeerId);
    final token = _header(headers, HomeShareProtocol.headerAuthToken);
    if (peerId == null || peerId.isEmpty) {
      return AuthResult.fail(401, 'missing peer id');
    }
    if (!isTrusted(peerId)) {
      return AuthResult.fail(403, 'not trusted');
    }
    final stored = expectedToken ?? tokenStore.get(peerId);
    if (stored == null || token != stored) {
      return AuthResult.fail(401, 'bad token');
    }
    final ts = _header(headers, HomeShareProtocol.headerTimestamp);
    final sig = _header(headers, HomeShareProtocol.headerSignature);
    if (ts != null && sig != null) {
      final ms = int.tryParse(ts);
      if (ms == null) return AuthResult.fail(401, 'bad timestamp');
      final skew = DateTime.now().toUtc().difference(
            DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
          );
      if (skew.abs() > HomeShareProtocol.clockSkew) {
        return AuthResult.fail(401, 'clock_skew');
      }
    }
    return AuthResult.ok(peerId);
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name.toLowerCase()) return e.value;
    }
    return null;
  }
}

class AuthResult {
  AuthResult._(this.ok, this.peerId, this.statusCode, this.message);
  factory AuthResult.ok(String peerId) => AuthResult._(true, peerId, 200, null);
  factory AuthResult.fail(int code, String message) =>
      AuthResult._(false, null, code, message);

  final bool ok;
  final String? peerId;
  final int statusCode;
  final String? message;
}
