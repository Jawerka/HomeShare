import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging/hs_log.dart';
import '../models/file_entry.dart';
import '../models/peer.dart';
import '../models/transfer_job.dart';
import '../models/transfer_state.dart';

/// Disk-backed outbox / transfer queue.
///
/// Invariant: a job becomes [TransferState.completed] only after SHA-256 verify
/// on the receiver (caller responsibility).
class OutboxQueue {
  OutboxQueue(this._dir);

  final Directory _dir;
  final Map<String, TransferJob> _jobs = {};
  final _controller = StreamController<List<TransferJob>>.broadcast();

  Stream<List<TransferJob>> get changes => _controller.stream;

  static Future<OutboxQueue> open(Directory dataDir) async {
    final dir = Directory('${dataDir.path}${Platform.pathSeparator}outbox');
    await dir.create(recursive: true);
    final q = OutboxQueue(dir);
    await q._load();
    return q;
  }

  Future<void> _load() async {
    _jobs.clear();
    await for (final entity in _dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final map =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final job = TransferJob.fromJson(Map<String, Object?>.from(map));
        // Do not auto-clear failed jobs on startup.
        if (job.state == TransferState.transferring ||
            job.state == TransferState.offering ||
            job.state == TransferState.verifying) {
          job.state = TransferState.pending;
        }
        _jobs[job.id] = job;
      } catch (e, st) {
        HsLog.core.warning('Skipping corrupt outbox file ${entity.path}', e, st);
      }
    }
    _emit();
  }

  List<TransferJob> list({bool includeTerminal = true}) {
    final all = _jobs.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (includeTerminal) return all;
    return all.where((j) => !j.isTerminal).toList();
  }

  TransferJob? get(String id) => _jobs[id];

  Future<TransferJob> enqueue({
    required String id,
    required PeerId peerId,
    required TransferDirection direction,
    required TransferKind kind,
    required String name,
    required int totalBytes,
    String? localPath,
    String? sha256,
    List<FileEntry> manifest = const [],
  }) async {
    final job = TransferJob(
      id: id,
      peerId: peerId,
      direction: direction,
      kind: kind,
      name: name,
      totalBytes: totalBytes,
      localPath: localPath,
      sha256: sha256,
      manifest: manifest,
    );
    _jobs[id] = job;
    await _persist(job);
    _emit();
    return job;
  }

  Future<void> update(
    String id, {
    TransferState? state,
    int? transferredBytes,
    String? errorMessage,
    String? sha256,
    int? retryCount,
    bool clearError = false,
    bool persist = true,
  }) async {
    final existing = _jobs[id];
    if (existing == null) return;
    final updated = existing.copyWith(
      state: state,
      transferredBytes: transferredBytes,
      errorMessage: clearError ? null : errorMessage,
      sha256: sha256,
      retryCount: retryCount,
    );
    if (clearError) updated.errorMessage = null;
    _jobs[id] = updated;
    if (persist) {
      await _persist(updated);
    }
    _emit();
  }

  /// Mark completed — only call after SHA-256 verify succeeded.
  Future<void> ackCompleted(String id) async {
    await update(id, state: TransferState.completed, clearError: true);
  }

  Future<void> markFailed(String id, String message) async {
    await update(id, state: TransferState.failed, errorMessage: message);
  }

  /// Transport errors must not burn retry budget.
  Future<void> markTransportRetry(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    await update(id, state: TransferState.pending, clearError: true);
  }

  Future<void> bumpAuthFailure(String id) async {
    await update(
      id,
      state: TransferState.failed,
      errorMessage: 'auth_required',
    );
  }

  Future<void> markCancelled(String id) async {
    await update(id, state: TransferState.cancelled, clearError: true);
  }

  /// Re-queue a failed/cancelled/paused job for another attempt.
  Future<void> retry(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    await update(
      id,
      state: TransferState.pending,
      transferredBytes: 0,
      clearError: true,
      retryCount: job.retryCount + 1,
    );
  }

  Future<void> remove(String id) async {
    _jobs.remove(id);
    final file = _fileFor(id);
    if (await file.exists()) await file.delete();
    _emit();
  }

  Future<void> _persist(TransferJob job) async {
    await _dir.create(recursive: true);
    await _fileFor(job.id).writeAsString(
      const JsonEncoder.withIndent('  ').convert(job.toJson()),
    );
  }

  File _fileFor(String id) =>
      File('${_dir.path}${Platform.pathSeparator}$id.json');

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(list());
    }
  }

  Future<void> close() async {
    await _controller.close();
  }
}
