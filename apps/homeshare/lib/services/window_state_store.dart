import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:homeshare_core/homeshare_core.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

/// Persists Windows window bounds across launches.
class WindowStateStore {
  WindowStateStore._();

  static File get _file {
    final local = Platform.environment['LOCALAPPDATA'];
    final dir = Directory(
      p.join(local ?? Directory.systemTemp.path, 'HomeShare'),
    );
    dir.createSync(recursive: true);
    return File(p.join(dir.path, 'window_state.json'));
  }

  static Future<Rect?> loadBounds() async {
    try {
      final file = _file;
      if (!await file.exists()) return null;
      final map =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final left = (map['left'] as num?)?.toDouble();
      final top = (map['top'] as num?)?.toDouble();
      final width = (map['width'] as num?)?.toDouble();
      final height = (map['height'] as num?)?.toDouble();
      if (left == null || top == null || width == null || height == null) {
        return null;
      }
      return Rect.fromLTWH(left, top, width, height);
    } catch (e, st) {
      HsLog.app.warning('WindowStateStore.loadBounds failed', e, st);
      return null;
    }
  }

  static Future<bool> loadMaximized() async {
    try {
      final file = _file;
      if (!await file.exists()) return false;
      final map =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map['maximized'] == true;
    } catch (e, st) {
      HsLog.app.warning('WindowStateStore.loadMaximized failed', e, st);
      return false;
    }
  }

  static Future<void> save({
    required Rect bounds,
    required bool maximized,
  }) async {
    final file = _file;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'left': bounds.left,
        'top': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
        'maximized': maximized,
      }),
    );
  }

  /// Clamp so at least 80x80 of the window stays on the primary display.
  static Rect clampToVisible(Rect bounds) {
    const minW = 360.0;
    const minH = 520.0;
    var w = bounds.width < minW ? minW : bounds.width;
    var h = bounds.height < minH ? minH : bounds.height;
    // Soft clamp: keep origin near zero if absurdly off-screen.
    var left = bounds.left;
    var top = bounds.top;
    if (left < -w + 80) left = 40;
    if (top < -40) top = 40;
    if (left > 4000) left = 40;
    if (top > 3000) top = 40;
    return Rect.fromLTWH(left, top, w, h);
  }
}

/// Debounced saver hooked from [WindowListener].
class WindowStateSaver {
  Timer? _debounce;

  void scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        if (await windowManager.isMinimized()) return;
        final maximized = await windowManager.isMaximized();
        final bounds = await windowManager.getBounds();
        await WindowStateStore.save(
          bounds: bounds,
          maximized: maximized,
        );
      } catch (e, st) {
        HsLog.app.warning('WindowStateSaver scheduleSave failed', e, st);
      }
    });
  }

  void dispose() => _debounce?.cancel();
}
