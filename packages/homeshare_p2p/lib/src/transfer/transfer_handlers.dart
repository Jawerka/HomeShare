import 'dart:convert';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:shelf/shelf.dart';

import '../protocol/constants.dart';
import '../protocol/http_helpers.dart';
import 'transfer_session.dart';

/// Transfer offer / blob / finalize / status handlers (SRP peel from PeerServer).
class TransferHandlers {
  TransferHandlers({
    required this.config,
    required this.inboxWriter,
    required this.sessions,
    required this.requireAuth,
    required this.peerIdFrom,
    required this.remoteHost,
    required this.touchPeerOnline,
    required this.diskSpaceForPath,
    this.onEvent,
    this.onReceiveUpdate,
  });

  final AppConfig config;
  final InboxWriter inboxWriter;
  final Map<String, TransferSession> sessions;
  final Response? Function(Request request, String method, String path)
      requireAuth;
  final String? Function(Request request) peerIdFrom;
  final String? Function(Request request) remoteHost;
  final Future<void> Function(String peerId, {String? host}) touchPeerOnline;
  final Future<DiskSpaceReport> Function(String path) diskSpaceForPath;
  final void Function(String kind, String message)? onEvent;
  final void Function(TransferSession session)? onReceiveUpdate;

  Future<Response> offer(Request request) async {
    final auth = requireAuth(request, 'POST', request.requestedUri.path);
    if (auth != null) return auth;

    final peerId = peerIdFrom(request)!;
    await touchPeerOnline(peerId, host: remoteHost(request));
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final transferId = body['transfer_id'] as String;
    final size = (body['size'] as num).toInt();
    final name = body['name'] as String;
    final kind = (body['kind'] as String?) == 'dir'
        ? TransferKind.dir
        : TransferKind.file;
    final sha256 = body['sha256'] as String?;

    if (sessions.containsKey(transferId) &&
        sessions[transferId]!.state == TransferState.completed) {
      return jsonError('conflict', 'Transfer already completed', status: 409);
    }

    if (size < 0 || size > config.maxTransferBytes) {
      onEvent?.call('error', 'size_limit for $name ($size bytes)');
      return jsonOk(
        {
          'error': 'size_limit',
          'max_bytes': config.maxTransferBytes,
          'required_bytes': size,
        },
        status: 413,
      );
    }

    final space = await diskSpaceForPath(config.inboxDir);
    if (!space.probeOk) {
      onEvent?.call('error', 'disk_probe_failed for inbox ${config.inboxDir}');
      return jsonOk(
        {
          'error': 'disk_probe_failed',
          'path': space.path,
        },
        status: 507,
      );
    }
    if (!space.hasRoomFor(size)) {
      onEvent?.call('error', 'disk_full for $name ($size bytes)');
      return jsonOk(
        {
          'error': 'disk_full',
          'inbox_free_bytes': space.freeBytes,
          'required_bytes': size,
        },
        status: 507,
      );
    }

    final manifest = <FileEntry>[];
    final rawManifest = body['manifest'];
    if (rawManifest is List) {
      if (rawManifest.length > config.maxManifestEntries) {
        return jsonOk(
          {
            'error': 'manifest_limit',
            'max_entries': config.maxManifestEntries,
            'required_entries': rawManifest.length,
          },
          status: 413,
        );
      }
      for (final item in rawManifest) {
        if (item is Map) {
          try {
            final path = PathSanitize.sanitizeRelative(item['path'] as String);
            manifest.add(
              FileEntry(
                path: path,
                size: (item['size'] as num).toInt(),
                sha256: item['sha256'] as String?,
              ),
            );
          } on PathSanitizeException catch (e) {
            return jsonError('path_invalid', '$e');
          }
        }
      }
    }

    await inboxWriter.ensureReady();
    final existing = sessions[transferId];
    final resume = existing?.receivedBytes ??
        await inboxWriter.receivedBytes(transferId);

    final session = TransferSession(
      transferId: transferId,
      fromPeerId: peerId,
      name: name,
      kind: kind,
      totalBytes: size,
      sha256: sha256,
      manifest: manifest,
    )
      ..receivedBytes = resume
      ..state = TransferState.transferring;
    sessions[transferId] = session;
    onReceiveUpdate?.call(session);
    onEvent?.call('transfer', 'Receiving $name ($size bytes)');

    return jsonOk({
      'status': 'ready',
      'resume_offset': resume,
      'inbox_free_bytes': space.freeBytes,
    });
  }

  Future<Response> blob(Request request, String id) async {
    final auth = requireAuth(request, 'PUT', request.requestedUri.path);
    if (auth != null) return auth;

    final session = sessions[id];
    if (session == null) {
      return jsonError('unknown_transfer', 'Unknown transfer', status: 404);
    }

    final relativePath = request.headers[HomeShareProtocol.headerPath] ??
        HomeShareProtocol.blobRelativePath;
    try {
      PathSanitize.sanitizeRelative(relativePath);
    } on PathSanitizeException catch (e) {
      return jsonError('path_invalid', '$e');
    }

    final offsetHeader = request.headers[HomeShareProtocol.headerUploadOffset];
    final offset = int.tryParse(offsetHeader ?? '0') ?? 0;

    late InboxWriteSession tmp;
    try {
      tmp = await inboxWriter.openWrite(
        transferId: id,
        relativePath: relativePath,
        offset: offset,
      );
    } on BlobWriteConflictException {
      return jsonError(
        'write_conflict',
        'Concurrent blob write for this transfer',
        status: 409,
      );
    }
    var written = offset;
    try {
      await for (final chunk in request.read()) {
        await tmp.add(chunk);
        written += chunk.length;
      }
      await tmp.close();
    } catch (e) {
      await tmp.abort();
      rethrow;
    }

    session.perFileReceived[relativePath] = written;
    if (session.kind == TransferKind.file) {
      session.receivedBytes = written;
    } else {
      session.receivedBytes =
          session.perFileReceived.values.fold(0, (a, b) => a + b);
    }
    onReceiveUpdate?.call(session);

    return jsonOk({
      'received': session.receivedBytes,
      'status': 'writing',
    });
  }

  /// Verify SHA-256 (file or dir entries) then atomically move into inbox.
  Future<Response> finalize(Request request, String id) async {
    final auth = requireAuth(request, 'POST', request.requestedUri.path);
    if (auth != null) return auth;

    final session = sessions[id];
    if (session == null) {
      return jsonError('unknown_transfer', 'Unknown transfer', status: 404);
    }

    try {
      session.state = TransferState.verifying;
      final bodyRaw = await request.readAsString();
      Map<String, dynamic> body = {};
      if (bodyRaw.isNotEmpty) {
        body = jsonDecode(bodyRaw) as Map<String, dynamic>;
      }

      if (session.kind == TransferKind.dir) {
        for (final entry in session.manifest) {
          if (entry.sha256 == null) continue;
          final actual = await inboxWriter.hashTemp(
            transferId: id,
            relativePath: entry.path,
          );
          if (actual != entry.sha256) {
            throw Sha256MismatchException(
              expected: entry.sha256!,
              actual: actual,
            );
          }
        }
        final dest = await inboxWriter.finalizeDirToInbox(
          transferId: id,
          desiredName: session.name,
        );
        session.state = TransferState.completed;
        onReceiveUpdate?.call(session);
        onEvent?.call('transfer', 'Saved directory ${dest.path}');
      } else {
        final expected = body['sha256'] as String? ?? session.sha256;
        final dest = await inboxWriter.finalizeToInbox(
          transferId: id,
          desiredName: session.name,
          expectedSha256: expected,
        );
        session.state = TransferState.completed;
        onReceiveUpdate?.call(session);
        onEvent?.call('transfer', 'Saved ${dest.path}');
      }

      return jsonOk({'status': 'completed'});
    } on Sha256MismatchException catch (e) {
      session.state = TransferState.failed;
      session.error = '$e';
      await inboxWriter.abort(id);
      onReceiveUpdate?.call(session);
      onEvent?.call('error', 'sha256 mismatch for ${session.name}');
      return jsonError('sha256_mismatch', '$e');
    } catch (e) {
      session.state = TransferState.failed;
      session.error = '$e';
      onReceiveUpdate?.call(session);
      onEvent?.call('error', 'finalize failed: $e');
      return jsonError('finalize_failed', '$e', status: 500);
    }
  }

  Response status(Request request, String id) {
    final session = sessions[id];
    if (session == null) {
      return jsonError('unknown_transfer', 'Unknown transfer', status: 404);
    }
    return jsonOk(session.statusJson());
  }
}
