import 'file_entry.dart';
import 'peer.dart';
import 'transfer_state.dart';

/// Kind of payload being transferred.
enum TransferKind { file, dir }

/// Persisted outbox / inbox transfer job.
class TransferJob {
  TransferJob({
    required this.id,
    required this.peerId,
    required this.direction,
    required this.kind,
    required this.name,
    required this.totalBytes,
    this.state = TransferState.pending,
    this.transferredBytes = 0,
    this.sha256,
    this.localPath,
    this.manifest = const [],
    this.errorMessage,
    this.retryCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final PeerId peerId;
  final TransferDirection direction;
  final TransferKind kind;
  final String name;
  final int totalBytes;
  TransferState state;
  int transferredBytes;
  String? sha256;
  String? localPath;
  List<FileEntry> manifest;
  String? errorMessage;
  int retryCount;
  final DateTime createdAt;
  DateTime updatedAt;

  int get progressPercent {
    if (totalBytes <= 0) return 0;
    final p = ((transferredBytes * 100) / totalBytes).floor();
    if (p < 0) return 0;
    if (p > 100) return 100;
    return p;
  }

  bool get isTerminal =>
      state == TransferState.completed ||
      state == TransferState.failed ||
      state == TransferState.cancelled;

  TransferJob copyWith({
    TransferState? state,
    int? transferredBytes,
    String? sha256,
    String? localPath,
    List<FileEntry>? manifest,
    String? errorMessage,
    int? retryCount,
    DateTime? updatedAt,
  }) {
    return TransferJob(
      id: id,
      peerId: peerId,
      direction: direction,
      kind: kind,
      name: name,
      totalBytes: totalBytes,
      state: state ?? this.state,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      sha256: sha256 ?? this.sha256,
      localPath: localPath ?? this.localPath,
      manifest: manifest ?? this.manifest,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'peer_id': peerId.value,
        'direction': direction.name,
        'kind': kind.name,
        'name': name,
        'total_bytes': totalBytes,
        'state': state.wireName,
        'transferred_bytes': transferredBytes,
        if (sha256 != null) 'sha256': sha256,
        if (localPath != null) 'local_path': localPath,
        'manifest': manifest.map((e) => e.toJson()).toList(),
        if (errorMessage != null) 'error_message': errorMessage,
        'retry_count': retryCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory TransferJob.fromJson(Map<String, Object?> json) {
    final manifestRaw = json['manifest'];
    final manifest = <FileEntry>[];
    if (manifestRaw is List) {
      for (final item in manifestRaw) {
        if (item is Map<String, Object?>) {
          manifest.add(FileEntry.fromJson(item));
        } else if (item is Map) {
          manifest.add(FileEntry.fromJson(Map<String, Object?>.from(item)));
        }
      }
    }
    return TransferJob(
      id: json['id']! as String,
      peerId: PeerId(json['peer_id']! as String),
      direction: TransferDirection.values.firstWhere(
        (e) => e.name == json['direction'],
        orElse: () => TransferDirection.send,
      ),
      kind: TransferKind.values.firstWhere(
        (e) => e.name == json['kind'],
        orElse: () => TransferKind.file,
      ),
      name: json['name']! as String,
      totalBytes: (json['total_bytes'] as num).toInt(),
      state: TransferStateJson.fromWire(json['state']! as String),
      transferredBytes: (json['transferred_bytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String?,
      localPath: json['local_path'] as String?,
      manifest: manifest,
      errorMessage: json['error_message'] as String?,
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at']! as String),
      updatedAt: DateTime.parse(json['updated_at']! as String),
    );
  }
}

enum TransferDirection { send, receive }
