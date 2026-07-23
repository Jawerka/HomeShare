/// Default transfer offer limits (override via [AppConfig]).
abstract final class HomeShareTransferLimits {
  /// Max single file / directory transfer size (50 GiB).
  static const maxTransferBytes = 50 * 1024 * 1024 * 1024;

  /// Max manifest entries for directory transfers.
  static const maxManifestEntries = 10000;
}
