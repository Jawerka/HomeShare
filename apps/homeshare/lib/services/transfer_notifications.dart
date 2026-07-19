import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Progress notification for Android transfers.
class TransferNotifications {
  TransferNotifications._();

  static final instance = TransferNotifications._();
  final _plugin = FlutterLocalNotificationsPlugin();
  var _ready = false;

  static const progressId = 42;
  static const doneId = 43;
  static const progressChannelId = 'homeshare_transfer_progress';
  static const doneChannelId = 'homeshare_transfer_done';

  Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        progressChannelId,
        'Прогресс HomeShare',
        description: 'Прогресс отправки и приёма файлов',
        importance: Importance.defaultImportance,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        doneChannelId,
        'Готово HomeShare',
        description: 'Завершение передач',
        importance: Importance.defaultImportance,
      ),
    );
    _ready = true;
  }

  Future<void> showProgress({
    required String title,
    required int percent,
  }) async {
    if (!_ready) return;
    final android = AndroidNotificationDetails(
      progressChannelId,
      'Прогресс HomeShare',
      channelDescription: 'Прогресс отправки и приёма файлов',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: percent.clamp(0, 100),
      ongoing: percent < 100,
      autoCancel: false,
    );
    await _plugin.show(
      progressId,
      title,
      '$percent%',
      NotificationDetails(android: android),
    );
  }

  Future<void> showDone(String message) async {
    if (!_ready) return;
    const android = AndroidNotificationDetails(
      doneChannelId,
      'Готово HomeShare',
      channelDescription: 'Завершение передач',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _plugin.show(
      doneId,
      'HomeShare',
      message,
      const NotificationDetails(android: android),
    );
  }

  /// Cancel ongoing progress notification, then show a done/error toast.
  Future<void> complete({required String message}) async {
    if (!_ready) return;
    await _plugin.cancel(progressId);
    await showDone(message);
  }

  Future<void> cancelProgress() async {
    if (!_ready) return;
    await _plugin.cancel(progressId);
  }
}
