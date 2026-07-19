import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:homeshare_p2p/homeshare_p2p.dart';
import 'package:http/http.dart' as http;

import 'cli_args.dart';

/// Detect a running HomeShare agent and forward CLI work to it.
class InstanceGate {
  InstanceGate({this.agentPort = HomeShareProtocol.agentPort});

  final int agentPort;

  Uri get _base => Uri.parse('http://127.0.0.1:$agentPort');

  /// Returns true if another instance accepted the handoff (caller should exit).
  Future<bool> handoffIfRunning(CliArgs args) async {
    if (!Platform.isWindows) return false;
    try {
      final health = await http
          .get(_base.replace(path: '/v1/health'))
          .timeout(const Duration(milliseconds: 400));
      if (health.statusCode != 200) return false;

      // Show window only for peer picker, --show, or a plain "open app" handoff
      // (not --background). Targeted Explorer sends stay in the tray.
      final needsPicker =
          args.sendPaths.isNotEmpty && args.targetPeerId == null;
      final show = args.show ||
          needsPicker ||
          (args.sendPaths.isEmpty &&
              args.targetPeerId == null &&
              !args.background);
      final body = jsonEncode({
        'paths': args.sendPaths,
        'peer_id': args.targetPeerId,
        'show': show,
      });
      final res = await http
          .post(
            _base.replace(path: '/v1/invoke'),
            headers: {'content-type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
