import 'dart:async';
import 'dart:io';

import 'package:homeshare_core/homeshare_core.dart';
import 'package:uuid/uuid.dart';

import '../protocol/errors.dart';
import 'transfer_client.dart';

/// Drives outbox jobs: enqueue → send → ack after remote verify.
class TransferCoordinator {
  TransferCoordinator({
    required this.outbox,
    required this.client,
    required this.resolvePeer,
    this.maxParallel = 2,
  });

  final OutboxQueue outbox;
  final TransferClient client;
  final TrustedPeer? Function(PeerId id) resolvePeer;
  final int maxParallel;

  final _uuid = const Uuid();
  var _active = 0;
  Timer? _timer;
  final _progress = StreamController<TransferJob>.broadcast();
  final _lastProgressAt = <String, DateTime>{};

  Stream<TransferJob> get progress => _progress.stream;

  void start({Duration interval = const Duration(seconds: 2)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => tick());
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<TransferJob> enqueueFile({
    required PeerId peerId,
    required File file,
  }) async {
    final id = _uuid.v4();
    final size = await file.length();
    return outbox.enqueue(
      id: id,
      peerId: peerId,
      direction: TransferDirection.send,
      kind: TransferKind.file,
      name: file.uri.pathSegments.last,
      totalBytes: size,
      localPath: file.path,
    );
  }

  Future<TransferJob> enqueueDirectory({
    required PeerId peerId,
    required Directory directory,
  }) async {
    final id = _uuid.v4();
    var total = 0;
    await for (final e in directory.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return outbox.enqueue(
      id: id,
      peerId: peerId,
      direction: TransferDirection.send,
      kind: TransferKind.dir,
      name: directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
      totalBytes: total,
      localPath: directory.path,
    );
  }

  Future<void> tick() async {
    if (_active >= maxParallel) return;
    // Oldest pending first so multi-file sends stay in selection order.
    final pending = outbox
        .list(includeTerminal: false)
        .where((j) => j.state == TransferState.pending)
        .toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    for (final job in pending) {
      if (_active >= maxParallel) break;
      _active++;
      unawaited(_run(job).whenComplete(() {
        _active--;
        // Start the next file immediately (do not wait for the 2s timer).
        unawaited(tick());
      }));
    }
  }

  Future<void> _run(TransferJob job) async {
    final peer = resolvePeer(job.peerId);
    if (peer == null || peer.host == null) {
      // Stay pending — peer offline, do not fail.
      return;
    }
    try {
      await outbox.update(job.id, state: TransferState.transferring);
      final path = job.localPath;
      if (path == null) {
        await outbox.markFailed(job.id, 'missing local_path');
        return;
      }
      if (job.kind == TransferKind.dir) {
        await client.sendDirectory(
          peer: peer,
          transferId: job.id,
          directory: Directory(path),
          onProgress: (t, total) async {
            await _reportProgress(job.id, t, total);
          },
        );
      } else {
        await client.sendFile(
          peer: peer,
          transferId: job.id,
          file: File(path),
          onProgress: (t, total) async {
            await _reportProgress(job.id, t, total);
          },
        );
      }
      // Remote finalize already verified sha256.
      await outbox.ackCompleted(job.id);
      _lastProgressAt.remove(job.id);
      final done = outbox.get(job.id);
      if (done != null) _progress.add(done);
    } on HomeShareException catch (e) {
      _lastProgressAt.remove(job.id);
      if (e.code == 'transport') {
        await outbox.markTransportRetry(job.id);
      } else if (e.code == 'auth_required' || e.code == 'not_trusted') {
        await outbox.bumpAuthFailure(job.id);
      } else if (e.code == 'disk_full') {
        await outbox.markFailed(job.id, 'disk_full');
      } else {
        await outbox.markFailed(job.id, e.message);
      }
    } on TimeoutException catch (e) {
      _lastProgressAt.remove(job.id);
      await outbox.markTransportRetry(job.id);
      // ignore: avoid_print
      print('transport timeout: $e');
    } on SocketException catch (e) {
      _lastProgressAt.remove(job.id);
      await outbox.markTransportRetry(job.id);
      // ignore: avoid_print
      print('transport: $e');
    } catch (e) {
      _lastProgressAt.remove(job.id);
      await outbox.markFailed(job.id, '$e');
    }
  }

  /// Throttle disk persist + UI events — every chunk used to flood the UI
  /// and crash Windows tray/taskbar native calls (0xc0000005).
  Future<void> _reportProgress(String jobId, int transferred, int total) async {
    final now = DateTime.now();
    final last = _lastProgressAt[jobId];
    final done = transferred >= total && total > 0;
    final due = last == null ||
        now.difference(last) >= const Duration(milliseconds: 250) ||
        done;
    if (!due) {
      // Keep in-memory progress without waking listeners every MiB.
      final existing = outbox.get(jobId);
      if (existing != null) {
        existing.transferredBytes = transferred;
      }
      return;
    }
    _lastProgressAt[jobId] = now;
    await outbox.update(
      jobId,
      transferredBytes: transferred,
      state: TransferState.transferring,
      persist: done,
    );
    final updated = outbox.get(jobId);
    if (updated != null) _progress.add(updated);
  }

  Future<void> close() async {
    stop();
    await _progress.close();
  }
}
