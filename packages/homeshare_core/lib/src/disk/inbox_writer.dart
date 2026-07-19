import 'dart:io';

import 'package:path/path.dart' as p;

import '../hash/sha256_stream.dart';
import 'path_sanitize.dart';

/// Writes incoming transfer bytes into a temp area, then atomically moves to inbox.
class InboxWriter {
  InboxWriter({
    required this.inboxDir,
  });

  final Directory inboxDir;

  Directory tmpRoot(String transferId) =>
      Directory(p.join(inboxDir.path, '.homeshare-tmp', transferId));

  Future<void> ensureReady() async {
    await inboxDir.create(recursive: true);
  }

  Future<File> openTempFile(String transferId, {String relativePath = 'payload'}) async {
    final safe = PathSanitize.sanitizeRelative(relativePath);
    final dir = tmpRoot(transferId);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, safe));
    await file.parent.create(recursive: true);
    return file;
  }

  /// Append [bytes] at [offset] to the temp file.
  Future<int> writeChunk({
    required String transferId,
    required String relativePath,
    required int offset,
    required List<int> bytes,
  }) async {
    final session = await openWrite(
      transferId: transferId,
      relativePath: relativePath,
      offset: offset,
    );
    try {
      await session.add(bytes);
      return await session.close();
    } catch (e) {
      await session.abort();
      rethrow;
    }
  }

  /// Open a streaming write at [offset] (one blob PUT).
  Future<InboxWriteSession> openWrite({
    required String transferId,
    required String relativePath,
    required int offset,
  }) async {
    final file = await openTempFile(transferId, relativePath: relativePath);
    final raf = await file.open(mode: FileMode.writeOnlyAppend);
    final length = await raf.length();
    if (offset < length) {
      await raf.truncate(offset);
      await raf.setPosition(offset);
    } else if (offset > length) {
      await raf.close();
      throw StateError('gap in upload: have $length, got offset $offset');
    } else {
      await raf.setPosition(offset);
    }
    return InboxWriteSession._(raf, offset);
  }

  Future<String> hashTemp({
    required String transferId,
    String relativePath = 'payload',
  }) async {
    final file = await openTempFile(transferId, relativePath: relativePath);
    return Sha256Stream.hashFile(file);
  }

  /// Verify optional [expectedSha256], then move into inbox with unique name.
  Future<File> finalizeToInbox({
    required String transferId,
    required String desiredName,
    String relativePath = 'payload',
    String? expectedSha256,
  }) async {
    await ensureReady();
    final tmp = await openTempFile(transferId, relativePath: relativePath);
    if (expectedSha256 != null) {
      final actual = await Sha256Stream.hashFile(tmp);
      if (actual != expectedSha256) {
        throw Sha256MismatchException(expected: expectedSha256, actual: actual);
      }
    }
    final safeName = p.basename(desiredName);
    final dest = await PathSanitize.uniqueFile(inboxDir, safeName);
    await tmp.rename(dest.path);
    await _cleanupTransfer(transferId);
    return dest;
  }

  /// Finalize a directory transfer: move entire tmp tree under inbox/`name`.
  Future<Directory> finalizeDirToInbox({
    required String transferId,
    required String desiredName,
  }) async {
    await ensureReady();
    final tmp = tmpRoot(transferId);
    final dest = await _uniqueDir(inboxDir, desiredName);
    await dest.create(recursive: true);
    await _copyTree(tmp, dest);
    await tmp.delete(recursive: true);
    return dest;
  }

  Future<void> abort(String transferId) async {
    final tmp = tmpRoot(transferId);
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  }

  Future<int> receivedBytes(String transferId, {String relativePath = 'payload'}) async {
    final file = File(
      p.join(tmpRoot(transferId).path, PathSanitize.sanitizeRelative(relativePath)),
    );
    if (!await file.exists()) return 0;
    return file.length();
  }

  Future<void> _cleanupTransfer(String transferId) async {
    final tmp = tmpRoot(transferId);
    if (await tmp.exists()) {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<Directory> _uniqueDir(Directory parent, String desired) async {
    var candidate = Directory(p.join(parent.path, desired));
    if (!await candidate.exists()) return candidate;
    for (var i = 1; i < 10000; i++) {
      candidate = Directory(p.join(parent.path, '$desired ($i)'));
      if (!await candidate.exists()) return candidate;
    }
    throw StateError('could not find unique dir for $desired');
  }

  Future<void> _copyTree(Directory from, Directory to) async {
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: from.path);
      final targetPath = p.join(to.path, rel);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await File(targetPath).parent.create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }
}

class Sha256MismatchException implements Exception {
  Sha256MismatchException({required this.expected, required this.actual});
  final String expected;
  final String actual;
  @override
  String toString() =>
      'Sha256MismatchException: expected=$expected actual=$actual';
}

/// Streaming writer for a single blob PUT.
class InboxWriteSession {
  InboxWriteSession._(this._raf, this._offset);
  final RandomAccessFile _raf;
  int _offset;
  var _closed = false;

  Future<void> add(List<int> bytes) async {
    await _raf.writeFrom(bytes);
    _offset += bytes.length;
  }

  Future<int> close() async {
    if (!_closed) {
      await _raf.close();
      _closed = true;
    }
    return _offset;
  }

  Future<void> abort() async {
    if (!_closed) {
      try {
        await _raf.close();
      } catch (_) {}
      _closed = true;
    }
  }
}

