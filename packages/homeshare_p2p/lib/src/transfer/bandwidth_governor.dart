import 'dart:async';
import 'dart:math';

/// Adaptive byte-rate limiter: AIMD toward LAN capacity, backs off under RTT pressure.
class BandwidthGovernor {
  BandwidthGovernor({
    this.minBytesPerSec = 256 * 1024,
    this.maxBytesPerSec = 80 * 1024 * 1024,
    this.initialBytesPerSec = 8 * 1024 * 1024,
  }) : _targetBps = initialBytesPerSec.toDouble();

  final int minBytesPerSec;
  final int maxBytesPerSec;
  final int initialBytesPerSec;

  double _targetBps;
  double _ewmaRttMs = 40;
  double _peakBps = 0;
  DateTime? _lastStableUp;

  /// Current chunk size (1–4 MiB) based on target rate.
  int get chunkSize {
    if (_targetBps >= 24 * 1024 * 1024) return 4 * 1024 * 1024;
    if (_targetBps >= 12 * 1024 * 1024) return 2 * 1024 * 1024;
    return 1024 * 1024;
  }

  /// How many PUTs may be in flight.
  int get maxInFlight => _targetBps >= 16 * 1024 * 1024 ? 2 : 1;

  double get targetBytesPerSec => _targetBps;

  /// Call after each completed PUT.
  void observePut({required int bytes, required Duration elapsed}) {
    final ms = max(1, elapsed.inMilliseconds);
    _ewmaRttMs = _ewmaRttMs * 0.7 + ms * 0.3;
    final bps = bytes * 1000.0 / ms;
    if (bps > _peakBps) _peakBps = bps;

    final expectedMs = bytes * 1000.0 / max(_targetBps, 1);
    if (ms > expectedMs * 2.2 || ms > _ewmaRttMs * 2.5) {
      _targetBps = max(minBytesPerSec.toDouble(), _targetBps * 0.7);
      _lastStableUp = null;
      return;
    }

    final now = DateTime.now();
    if (_lastStableUp == null) {
      _lastStableUp = now;
      return;
    }
    if (now.difference(_lastStableUp!) >= const Duration(seconds: 12)) {
      final ceiling = _peakBps > 0 ? _peakBps * 0.92 : maxBytesPerSec.toDouble();
      _targetBps = min(
        maxBytesPerSec.toDouble(),
        min(ceiling, _targetBps * 1.1),
      );
      _lastStableUp = now;
    }
  }

  /// Pace the next chunk so average rate tracks [_targetBps].
  Future<void> pace({required int bytesJustSent, required Stopwatch putWatch}) async {
    final elapsed = putWatch.elapsedMicroseconds / 1e6;
    final ideal = bytesJustSent / max(_targetBps, 1);
    final sleep = ideal - elapsed;
    if (sleep > 0.002) {
      await Future<void>.delayed(
        Duration(microseconds: (sleep * 1e6).round()),
      );
    }
  }
}
