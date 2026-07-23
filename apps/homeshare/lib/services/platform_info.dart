import 'dart:io';

/// True on desktop OS (not web).
bool get isDesktop =>
    !bool.fromEnvironment('dart.library.js_util') &&
    (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
