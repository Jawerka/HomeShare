import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Durable device profile that survives app reinstalls better than app-support.
class DeviceProfile {
  DeviceProfile({this.displayName, this.preferredLanHost});

  String? displayName;
  String? preferredLanHost;

  Map<String, Object?> toJson() => {
        if (displayName != null) 'display_name': displayName,
        if (preferredLanHost != null) 'preferred_lan_host': preferredLanHost,
      };

  factory DeviceProfile.fromJson(Map<String, Object?> json) => DeviceProfile(
        displayName: json['display_name'] as String?,
        preferredLanHost: json['preferred_lan_host'] as String?,
      );

  static Future<File> _file() async {
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'];
      final dir = Directory(
        p.join(local ?? Directory.systemTemp.path, 'HomeShare'),
      );
      await dir.create(recursive: true);
      return File(p.join(dir.path, 'device_profile.json'));
    }
    // Android: external app files often outlive clear-cache; also used for restore.
    final ext = await getExternalStorageDirectory();
    final base = ext ?? await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'HomeShare'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'device_profile.json'));
  }

  static Future<DeviceProfile?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final map =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return DeviceProfile.fromJson(Map<String, Object?>.from(map));
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }
}
