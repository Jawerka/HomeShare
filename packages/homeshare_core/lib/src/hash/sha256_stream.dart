import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Streaming SHA-256 for large files (never loads whole file into RAM).
class Sha256Stream {
  final _digest = AccumulatorSink<Digest>();
  late final ByteConversionSink _sink = sha256.startChunkedConversion(_digest);

  void add(List<int> chunk) => _sink.add(chunk);

  String finalize() {
    _sink.close();
    return _digest.events.single.toString();
  }

  /// Hash a file from disk in chunks (background isolate — keeps UI responsive).
  static Future<String> hashFile(
    File file, {
    int chunkSize = 1024 * 1024,
  }) {
    return Isolate.run(() => _hashFilePath(file.path, chunkSize));
  }

  static Future<String> _hashFilePath(String path, int chunkSize) async {
    final hasher = Sha256Stream();
    final raf = await File(path).open();
    try {
      while (true) {
        final chunk = await raf.read(chunkSize);
        if (chunk.isEmpty) break;
        hasher.add(chunk);
      }
    } finally {
      await raf.close();
    }
    return hasher.finalize();
  }

  static String hashBytes(List<int> bytes) => sha256.convert(bytes).toString();
}

/// Sink that accumulates digest events (crypto package pattern).
class AccumulatorSink<T> implements EventSink<T> {
  final List<T> events = [];
  var _closed = false;

  @override
  void add(T event) {
    if (_closed) throw StateError('Sink closed');
    events.add(event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_closed) throw StateError('Sink closed');
    throw error;
  }

  @override
  void close() {
    _closed = true;
  }
}
