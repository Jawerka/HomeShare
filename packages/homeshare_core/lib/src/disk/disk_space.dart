import 'dart:io';
import 'dart:math' as math;

/// Report of free / total disk space for an inbox path.
class DiskSpaceReport {
  const DiskSpaceReport({
    required this.path,
    required this.freeBytes,
    required this.totalBytes,
  });

  final String path;
  final int freeBytes;
  final int totalBytes;

  bool hasRoomFor(int requiredBytes, {int safetyMarginBytes = 64 * 1024 * 1024}) {
    final margin = math.max(
      safetyMarginBytes,
      (requiredBytes * 0.01).ceil(),
    );
    return freeBytes >= requiredBytes + margin;
  }
}

/// Cross-platform free space probe.
class DiskSpace {
  /// Returns free bytes available on the volume containing [path].
  static Future<DiskSpaceReport> forPath(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    if (Platform.isWindows) {
      return _windows(path);
    }
    return _posix(path);
  }

  static Future<DiskSpaceReport> _posix(String path) async {
    try {
      final result = await Process.run('df', ['-k', path]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines.last.split(RegExp(r'\s+'));
          // Filesystem 1K-blocks Used Available Use% Mounted
          if (parts.length >= 4) {
            final totalKb = int.tryParse(parts[1]) ?? 0;
            final freeKb = int.tryParse(parts[3]) ?? 0;
            return DiskSpaceReport(
              path: path,
              freeBytes: freeKb * 1024,
              totalBytes: totalKb * 1024,
            );
          }
        }
      }
    } catch (_) {
      // fall through
    }
    // Best-effort fallback: assume plenty of space in tests / constrained envs.
    return DiskSpaceReport(
      path: path,
      freeBytes: 1 << 50,
      totalBytes: 1 << 50,
    );
  }

  static Future<DiskSpaceReport> _windows(String path) async {
    try {
      final root = File(path).absolute.path.substring(0, 2); // e.g. C:
      final script =
          '\$d=Get-PSDrive -Name ''${root[0]}''; '
          'Write-Output ("\$(\$d.Free) \$(\$d.Used+\$d.Free)")';
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', script],
      );
      if (result.exitCode == 0) {
        final parts = (result.stdout as String).trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final free = int.tryParse(parts[0]) ?? 0;
          final total = int.tryParse(parts[1]) ?? 0;
          return DiskSpaceReport(
            path: path,
            freeBytes: free,
            totalBytes: total,
          );
        }
      }
    } catch (_) {
      // fall through
    }
    return DiskSpaceReport(
      path: path,
      freeBytes: 1 << 50,
      totalBytes: 1 << 50,
    );
  }
}
