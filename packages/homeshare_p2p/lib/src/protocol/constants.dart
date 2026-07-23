import 'package:homeshare_core/homeshare_core.dart';

/// Wire protocol constants for HomeShare v1.
abstract final class HomeShareProtocol {
  static const version = HomeShareWire.version;
  static const mdnsType = '_homeshare._tcp';
  static const pathPrefix = HomeShareWire.pathPrefix;

  static const discoveryPort = HomeSharePorts.discovery;
  static const p2pPort = HomeSharePorts.p2p;
  static const httpsPort = HomeSharePorts.https;
  static const webPort = HomeSharePorts.web;
  static const agentPort = HomeSharePorts.agent;

  static const headerPeerId = HomeShareWire.headerPeerId;
  static const headerAuthToken = HomeShareWire.headerAuthToken;
  static const headerTimestamp = HomeShareWire.headerTimestamp;
  static const headerSignature = HomeShareWire.headerSignature;
  static const headerPath = HomeShareWire.headerPath;
  static const headerUploadOffset = HomeShareWire.headerUploadOffset;
  static const headerUploadTotal = HomeShareWire.headerUploadTotal;
  static const headerUploadSha256 = HomeShareWire.headerUploadSha256;

  static const blobRelativePath = HomeShareWire.blobRelativePath;

  static const chunkSize = 1024 * 1024; // 1 MiB
  static const clockSkew = Duration(minutes: 5);
}
