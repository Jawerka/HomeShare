import 'dart:convert';
import 'dart:io';

class CliArgs {
  CliArgs({
    this.background = false,
    this.show = false,
    this.targetPeerId,
    this.sendPaths = const [],
  });

  final bool background;
  /// Force show the main window (overrides start-hidden default on Windows).
  final bool show;
  final String? targetPeerId;
  final List<String> sendPaths;

  static CliArgs parse(List<String> args) {
    var background = false;
    var show = false;
    String? target;
    final paths = <String>[];
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--background') {
        background = true;
      } else if (a == '--show') {
        show = true;
      } else if (a == '--target' && i + 1 < args.length) {
        target = args[++i];
      } else if (a == '--send') {
        // following args until next flag are paths
        while (i + 1 < args.length && !args[i + 1].startsWith('--')) {
          paths.addAll(expandPathArg(args[++i]));
        }
      } else if (!a.startsWith('--')) {
        paths.addAll(expandPathArg(a));
      }
    }
    return CliArgs(
      background: background,
      show: show,
      targetPeerId: target,
      sendPaths: paths,
    );
  }

  /// Explorer MultiSelectModel=Player may pass several quoted paths in one argv.
  static List<String> expandPathArg(String arg) {
    final trimmed = arg.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final asFile = File(trimmed);
      final asDir = Directory(trimmed);
      if (asFile.existsSync() || asDir.existsSync()) {
        return [trimmed];
      }
    } on FileSystemException {
      // Invalid path characters (e.g. multi-quoted argv) — parse quotes below.
    }
    if (!trimmed.contains('"')) {
      return [trimmed];
    }
    final out = <String>[];
    final re = RegExp(r'"([^"]+)"');
    for (final m in re.allMatches(trimmed)) {
      final path = m.group(1);
      if (path != null && path.isNotEmpty) out.add(path);
    }
    return out.isEmpty ? [trimmed] : out;
  }

  @override
  String toString() => jsonEncode({
        'background': background,
        'show': show,
        'target': targetPeerId,
        'paths': sendPaths,
      });
}
