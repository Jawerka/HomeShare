import 'dart:math';

/// Generates a 6-digit pairing PIN.
class PairingPin {
  PairingPin(this.value, {DateTime? createdAt, this.ttl = const Duration(minutes: 2)})
      : createdAt = createdAt ?? DateTime.now().toUtc();

  final String value;
  final DateTime createdAt;
  final Duration ttl;

  bool get isExpired =>
      DateTime.now().toUtc().difference(createdAt) > ttl;

  static PairingPin generate({Random? random}) {
    final r = random ?? Random.secure();
    final n = r.nextInt(1000000);
    return PairingPin(n.toString().padLeft(6, '0'));
  }
}
