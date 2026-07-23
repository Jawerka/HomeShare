import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:homeshare_core/homeshare_core.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_headers.dart';
import '../protocol/constants.dart';
import '../protocol/errors.dart';
import '../protocol/http_helpers.dart';
import 'bandwidth_governor.dart';

typedef ProgressCallback = void Function(int transferred, int total);

/// Sends files / directories to a trusted peer.
class TransferClient {
  TransferClient({
    required this.identity,
    required this.tokenStore,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 120),
    BandwidthGovernor? governor,
  })  : _http = httpClient ?? http.Client(),
        governor = governor ?? BandwidthGovernor();

  final DeviceIdentity identity;
  final TokenStore tokenStore;
  final http.Client _http;
  final Duration requestTimeout;
  final BandwidthGovernor governor;

  AuthHeaders get _auth =>
      AuthHeaders(identity: identity, tokenStore: tokenStore);

  Future<void> sendFile({
    required TrustedPeer peer,
    required String transferId,
    required File file,
    String? sha256,
    ProgressCallback? onProgress,
  }) async {
    if (peer.host == null) {
      throw HomeShareException.transport('peer host unknown');
    }
    final size = await file.length();
    final knownHash = sha256;
    final base = _base(peer);

    final offerBody = throwIfOfferFailed(
      await _postJson(
        peer,
        '$base${HomeShareProtocol.pathPrefix}/transfer/offer',
        {
          'transfer_id': transferId,
          'name': file.uri.pathSegments.last,
          'kind': 'file',
          'size': size,
          if (knownHash != null) 'sha256': knownHash,
          'file_count': 1,
        },
      ),
    );
    var offset = (offerBody['resume_offset'] as num?)?.toInt() ?? 0;

    final hasher = knownHash == null ? Sha256Stream() : null;
    if (hasher != null && offset > 0) {
      // Resume: re-hash prefix so finalize digest matches the full file.
      final rafHash = await file.open();
      try {
        var left = offset;
        while (left > 0) {
          final n = left.clamp(0, governor.chunkSize);
          final prefix = await rafHash.read(n);
          if (prefix.isEmpty) break;
          hasher.add(prefix);
          left -= prefix.length;
        }
      } finally {
        await rafHash.close();
      }
    }

    final raf = await file.open();
    try {
      await raf.setPosition(offset);
      while (offset < size) {
        final toRead = (size - offset).clamp(0, governor.chunkSize);
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) break;
        hasher?.add(chunk);
        final watch = Stopwatch()..start();
        await _putChunk(
          peer: peer,
          base: base,
          transferId: transferId,
          relativePath: HomeShareProtocol.blobRelativePath,
          offset: offset,
          total: size,
          chunk: chunk,
        );
        watch.stop();
        governor.observePut(bytes: chunk.length, elapsed: watch.elapsed);
        await governor.pace(bytesJustSent: chunk.length, putWatch: watch);
        offset += chunk.length;
        onProgress?.call(offset, size);
      }
    } finally {
      await raf.close();
    }

    final hash = knownHash ?? hasher!.finalize();
    await _finalize(
      peer: peer,
      base: base,
      transferId: transferId,
      body: {'sha256': hash},
    );
  }

  Future<void> sendDirectory({
    required TrustedPeer peer,
    required String transferId,
    required Directory directory,
    ProgressCallback? onProgress,
  }) async {
    if (peer.host == null) {
      throw HomeShareException.transport('peer host unknown');
    }
    final files = <File>[];
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    final manifest = <Map<String, Object?>>[];
    var total = 0;
    for (final f in files) {
      final rel = f.path
          .substring(directory.path.length)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/'), '');
      final size = await f.length();
      final hash = await Sha256Stream.hashFile(f);
      total += size;
      manifest.add({'path': rel, 'size': size, 'sha256': hash});
    }

    final base = _base(peer);
    throwIfOfferFailed(
      await _postJson(
        peer,
        '$base${HomeShareProtocol.pathPrefix}/transfer/offer',
        {
          'transfer_id': transferId,
          'name': directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
          'kind': 'dir',
          'size': total,
          'file_count': files.length,
          'manifest': manifest,
        },
      ),
    );

    var sent = 0;
    for (final entry in manifest) {
      final rel = entry['path']! as String;
      final size = entry['size']! as int;
      final hash = entry['sha256']! as String;
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        '${rel.replaceAll('/', Platform.pathSeparator)}',
      );
      var offset = 0;
      final raf = await file.open();
      try {
        while (offset < size) {
          final toRead = (size - offset).clamp(0, governor.chunkSize);
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;
          final watch = Stopwatch()..start();
          await _putChunk(
            peer: peer,
            base: base,
            transferId: transferId,
            relativePath: rel,
            offset: offset,
            total: size,
            chunk: chunk,
            fileSha256: hash,
          );
          watch.stop();
          governor.observePut(bytes: chunk.length, elapsed: watch.elapsed);
          await governor.pace(bytesJustSent: chunk.length, putWatch: watch);
          offset += chunk.length;
          sent += chunk.length;
          onProgress?.call(sent, total);
        }
      } finally {
        await raf.close();
      }
    }

    await _finalize(
      peer: peer,
      base: base,
      transferId: transferId,
      body: {'kind': 'dir'},
    );
  }

  Future<void> _finalize({
    required TrustedPeer peer,
    required String base,
    required String transferId,
    required Map<String, Object?> body,
  }) async {
    final finUri = Uri.parse(
      '$base${HomeShareProtocol.pathPrefix}/transfer/$transferId/finalize',
    );
    final finRes = await _http
        .post(
          finUri,
          headers: {
            ..._auth.forRequest(
              peerId: peer.peerId.value,
              method: 'POST',
              path: finUri.path,
            ),
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);
    if (finRes.statusCode != 200) {
      throw HomeShareException(
        'finalize_failed',
        finRes.body,
        statusCode: finRes.statusCode,
      );
    }
  }

  Future<void> _putChunk({
    required TrustedPeer peer,
    required String base,
    required String transferId,
    required String relativePath,
    required int offset,
    required int total,
    required List<int> chunk,
    String? fileSha256,
  }) async {
    final putUri = Uri.parse(
      '$base${HomeShareProtocol.pathPrefix}/transfer/$transferId/blob',
    );
    final headers = {
      ..._auth.forRequest(
        peerId: peer.peerId.value,
        method: 'PUT',
        path: putUri.path,
      ),
      'content-type': 'application/octet-stream',
      'content-range': 'bytes $offset-${offset + chunk.length - 1}/$total',
      HomeShareProtocol.headerUploadOffset: '$offset',
      HomeShareProtocol.headerUploadTotal: '$total',
      HomeShareProtocol.headerPath: relativePath,
      if (fileSha256 != null) HomeShareProtocol.headerUploadSha256: fileSha256,
    };
    final timeout = Duration(
      milliseconds: max(60000, (chunk.length / 1024).round() * 20),
    );
    final putRes =
        await _http.put(putUri, headers: headers, body: chunk).timeout(timeout);
    if (putRes.statusCode != 200) {
      throw HomeShareException(
        'upload_failed',
        putRes.body,
        statusCode: putRes.statusCode,
      );
    }
  }

  String _base(TrustedPeer peer) => 'http://${peer.host}:${peer.port}';

  Future<http.Response> _postJson(
    TrustedPeer peer,
    String url,
    Map<String, Object?> body,
  ) {
    final uri = Uri.parse(url);
    return _http
        .post(
          uri,
          headers: {
            ..._auth.forRequest(
              peerId: peer.peerId.value,
              method: 'POST',
              path: uri.path,
            ),
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);
  }

  void close() => _http.close();
}
