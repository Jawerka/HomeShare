import 'package:logging/logging.dart';

export 'package:logging/logging.dart' show Level;

/// Thin HomeShare logging facade over `package:logging`.
class HsLog {
  HsLog._();

  static bool _configured = false;

  /// Configure root logger once (console by default).
  static void setup({
    Level level = Level.INFO,
    void Function(LogRecord record)? onRecord,
  }) {
    if (_configured) return;
    _configured = true;
    hierarchicalLoggingEnabled = true;
    Logger.root.level = level;
    Logger.root.onRecord.listen(onRecord ?? _defaultPrint);
  }

  static void _defaultPrint(LogRecord record) {
    final buf = StringBuffer(
      '${record.time.toIso8601String()} [${record.level.name}] '
      '${record.loggerName}: ${record.message}',
    );
    if (record.error != null) {
      buf.write('\n  error: ${record.error}');
    }
    if (record.stackTrace != null) {
      buf.write('\n  ${record.stackTrace}');
    }
    // ignore: avoid_print
    print(buf);
  }

  static Logger of(String name) => Logger(name);

  static final core = Logger('homeshare.core');
  static final p2p = Logger('homeshare.p2p');
  static final app = Logger('homeshare.app');
  static final hub = Logger('homeshare.hub');
}
