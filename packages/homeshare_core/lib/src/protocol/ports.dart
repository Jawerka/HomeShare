/// Shared HomeShare port defaults (safe for core; p2p re-exports via protocol).
abstract final class HomeSharePorts {
  static const discovery = 45837;
  static const p2p = 45838;
  static const https = 45840;
  static const web = 8787;
  static const agent = 47831;
}

/// Shared wire path/header names used by client and server.
abstract final class HomeShareWire {
  static const version = 'v1';
  static const pathPrefix = '/homeshare/p2p';
  static const blobRelativePath = 'payload';

  static const headerPeerId = 'x-homeshare-peer-id';
  static const headerAuthToken = 'x-homeshare-auth-token';
  static const headerTimestamp = 'x-homeshare-timestamp';
  static const headerSignature = 'x-homeshare-signature';
  static const headerPath = 'x-homeshare-path';
  static const headerUploadOffset = 'x-homeshare-upload-offset';
  static const headerUploadTotal = 'x-homeshare-upload-total';
  static const headerUploadSha256 = 'x-homeshare-upload-sha256';
}
