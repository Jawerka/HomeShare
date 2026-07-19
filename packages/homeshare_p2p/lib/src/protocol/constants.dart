/// Wire protocol constants for HomeShare v1.
abstract final class HomeShareProtocol {
  static const version = 'v1';
  static const mdnsType = '_homeshare._tcp';
  static const pathPrefix = '/homeshare/p2p';

  static const discoveryPort = 45837;
  static const p2pPort = 45838;
  static const httpsPort = 45840;
  static const webPort = 8787;
  static const agentPort = 47831;

  static const headerPeerId = 'x-homeshare-peer-id';
  static const headerAuthToken = 'x-homeshare-auth-token';
  static const headerTimestamp = 'x-homeshare-timestamp';
  static const headerSignature = 'x-homeshare-signature';
  static const headerPath = 'x-homeshare-path';
  static const headerUploadOffset = 'x-homeshare-upload-offset';
  static const headerUploadTotal = 'x-homeshare-upload-total';
  static const headerUploadSha256 = 'x-homeshare-upload-sha256';

  static const chunkSize = 1024 * 1024; // 1 MiB
  static const clockSkew = Duration(minutes: 5);
}
