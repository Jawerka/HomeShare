import 'dart:io';

import 'package:path/path.dart' as p;

/// Rejects path traversal and absolute paths in transfer manifests.
class PathSanitize {
  /// Returns a normalized relative path or throws [PathSanitizeException].
  static String sanitizeRelative(String input) {
    var s = input.replaceAll('\\', '/').trim();
    if (s.isEmpty) {
      throw PathSanitizeException('empty path');
    }
    if (s.contains('\x00')) {
      throw PathSanitizeException('NUL in path');
    }
    if (p.isAbsolute(s) || s.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(s)) {
      throw PathSanitizeException('absolute path not allowed: $input');
    }
    final parts = <String>[];
    for (final part in s.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        throw PathSanitizeException('path traversal not allowed: $input');
      }
      parts.add(part);
    }
    if (parts.isEmpty) {
      throw PathSanitizeException('empty path after normalize: $input');
    }
    return parts.join('/');
  }

  /// Unique filename if [desired] already exists in [directory].
  static Future<File> uniqueFile(Directory directory, String desired) async {
    final base = p.basenameWithoutExtension(desired);
    final ext = p.extension(desired);
    var candidate = File(p.join(directory.path, desired));
    if (!await candidate.exists()) return candidate;
    for (var i = 1; i < 10000; i++) {
      candidate = File(p.join(directory.path, '$base ($i)$ext'));
      if (!await candidate.exists()) return candidate;
    }
    throw StateError('could not find unique name for $desired');
  }
}

class PathSanitizeException implements Exception {
  PathSanitizeException(this.message);
  final String message;
  @override
  String toString() => 'PathSanitizeException: $message';
}
