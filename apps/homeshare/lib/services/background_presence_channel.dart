import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Starts/stops the Android dataSync FGS that keeps the process receivable.
class BackgroundPresenceChannel {
  static const _channel = MethodChannel('homeshare/background_presence');

  static Future<void> start() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (e) {
      debugPrint('BackgroundPresence start failed: $e');
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('BackgroundPresence stop failed: $e');
    }
  }
}
