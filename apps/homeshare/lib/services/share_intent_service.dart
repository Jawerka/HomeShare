import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Android Share Intent → local file paths.
class ShareIntentService {
  static StreamSubscription<List<SharedMediaFile>>? _sub;

  static void listen(void Function(List<String> paths) onPaths) {
    if (kIsWeb || !Platform.isAndroid) return;

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      final paths =
          files.map((f) => f.path).where((p) => p.isNotEmpty).toList();
      if (paths.isNotEmpty) onPaths(paths);
    });

    _sub?.cancel();
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      final paths =
          files.map((f) => f.path).where((p) => p.isNotEmpty).toList();
      if (paths.isNotEmpty) onPaths(paths);
    });
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
