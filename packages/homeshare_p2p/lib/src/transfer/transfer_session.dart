import 'package:homeshare_core/homeshare_core.dart';

/// In-memory receive session for an incoming transfer.
class TransferSession {
  TransferSession({
    required this.transferId,
    required this.fromPeerId,
    required this.name,
    required this.kind,
    required this.totalBytes,
    this.sha256,
    this.manifest = const [],
  });

  final String transferId;
  final String fromPeerId;
  final String name;
  final TransferKind kind;
  final int totalBytes;
  final String? sha256;
  final List<FileEntry> manifest;

  int receivedBytes = 0;
  TransferState state = TransferState.offering;
  final Map<String, int> perFileReceived = {};
  String? error;

  Map<String, Object?> statusJson() => {
        'transfer_id': transferId,
        'name': name,
        'kind': kind.name,
        'total_bytes': totalBytes,
        'received_bytes': receivedBytes,
        'progress_percent': totalBytes == 0
            ? 0
            : ((receivedBytes * 100) / totalBytes).floor().clamp(0, 100),
        'state': state.name,
        if (error != null) 'error': error,
      };
}
