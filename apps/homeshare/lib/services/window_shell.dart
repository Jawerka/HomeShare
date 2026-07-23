import 'package:flutter/material.dart';
import 'package:homeshare_core/homeshare_core.dart';
import 'package:window_manager/window_manager.dart';

/// Windows window show/hide helpers. Empty catches are intentional (native AV).
class WindowShell {
  WindowShell._();

  static Future<void> showAndFocus() async {
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      HsLog.app.warning('Window show/focus failed', e, st);
    }
  }

  static Future<void> hideToTray() async {
    try {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    } catch (e, st) {
      HsLog.app.warning('Window hide failed', e, st);
    }
  }

  static Future<void> applyBounds(Rect bounds, {required bool maximized}) async {
    try {
      await windowManager.setBounds(bounds);
      if (maximized) await windowManager.maximize();
    } catch (e, st) {
      HsLog.app.warning('Window setBounds failed', e, st);
    }
  }
}
