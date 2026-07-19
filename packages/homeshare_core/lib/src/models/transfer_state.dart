/// Transfer lifecycle states for outbox jobs.
enum TransferState {
  pending,
  offering,
  transferring,
  verifying,
  completed,
  failed,
  paused,
  cancelled,
  partial,
}

extension TransferStateJson on TransferState {
  String get wireName => name;

  static TransferState fromWire(String value) {
    return TransferState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TransferState.pending,
    );
  }
}
