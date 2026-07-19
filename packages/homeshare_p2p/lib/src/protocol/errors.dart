/// Structured wire / transfer errors.
class HomeShareException implements Exception {
  HomeShareException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'HomeShareException($code): $message';

  static HomeShareException diskFull([String? detail]) => HomeShareException(
        'disk_full',
        detail ?? 'Not enough free disk space on receiver',
        statusCode: 507,
      );

  static HomeShareException authRequired([String? detail]) =>
      HomeShareException(
        'auth_required',
        detail ?? 'Authentication required or token invalid',
        statusCode: 401,
      );

  static HomeShareException notTrusted([String? detail]) => HomeShareException(
        'not_trusted',
        detail ?? 'Peer is not trusted',
        statusCode: 403,
      );

  static HomeShareException pathInvalid([String? detail]) => HomeShareException(
        'path_invalid',
        detail ?? 'Invalid relative path',
        statusCode: 400,
      );

  static HomeShareException conflict([String? detail]) => HomeShareException(
        'conflict',
        detail ?? 'Transfer id conflict',
        statusCode: 409,
      );

  static HomeShareException transport(String detail) => HomeShareException(
        'transport',
        detail,
      );
}
