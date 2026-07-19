import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/devices_screen.dart';
import 'screens/peer_picker_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/transfers_screen.dart';
import 'services/app_controller.dart';
import 'services/cli_args.dart';
import 'services/instance_gate.dart';
import 'services/share_intent_service.dart';
import 'services/window_state_store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final parsed = CliArgs.parse(args);

  // Second Explorer launch → hand off to the already running agent, then exit.
  if (!kIsWeb && Platform.isWindows) {
    final handed = await InstanceGate().handoffIfRunning(parsed);
    if (handed) {
      exit(0);
    }
  }

  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    final saved = await WindowStateStore.loadBounds();
    final maximized = await WindowStateStore.loadMaximized();
    final bounds = saved != null
        ? WindowStateStore.clampToVisible(saved)
        : const Rect.fromLTWH(100, 100, 420, 720);
    final options = WindowOptions(
      size: bounds.size,
      minimumSize: const Size(360, 520),
      title: 'HomeShare',
      skipTaskbar: true,
    );
    final needsPicker =
        parsed.sendPaths.isNotEmpty && parsed.targetPeerId == null;
    final shouldShow = parsed.show || needsPicker;
    await windowManager.waitUntilReadyToShow(options, () async {
      try {
        await windowManager.setBounds(bounds);
        if (maximized) await windowManager.maximize();
      } catch (_) {}
      if (shouldShow) {
        try {
          await windowManager.setSkipTaskbar(false);
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
      } else {
        try {
          await windowManager.hide();
        } catch (_) {}
      }
    });
  }

  final controller = AppController();
  controller.onRequestShowWindow = () async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  };

  try {
    await controller.init();
  } catch (e, st) {
    debugPrint('HomeShare init failed: $e\n$st');
    // Still show UI with error if possible.
  }

  if (parsed.sendPaths.isNotEmpty && parsed.targetPeerId != null) {
    // Explorer submenu → send in background; do not force-show the window.
    await controller.sendPaths(
      parsed.sendPaths,
      peerId: parsed.targetPeerId!,
    );
  } else if (parsed.sendPaths.isNotEmpty) {
    // Debounced merge so Explorer multi-select handoffs arrive before picker.
    controller.queuePendingSendPaths(parsed.sendPaths);
    if (!kIsWeb && Platform.isWindows) {
      try {
        await windowManager.setSkipTaskbar(false);
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }
  }

  runApp(HomeShareApp(
    controller: controller,
    background: parsed.background,
  ));
}

class HomeShareApp extends StatefulWidget {
  const HomeShareApp({
    super.key,
    required this.controller,
    this.background = false,
  });

  final AppController controller;
  final bool background;

  @override
  State<HomeShareApp> createState() => _HomeShareAppState();
}

class _HomeShareAppState extends State<HomeShareApp>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  List<String> _sharePaths = const [];
  var _trayReady = false;
  final _windowSaver = WindowStateSaver();
  Timer? _androidPresencePulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && Platform.isAndroid) {
      ShareIntentService.listen((paths) {
        if (!mounted) return;
        setState(() => _sharePaths = paths);
      });
      widget.controller.addListener(_onController);
      _scheduleAndroidPresencePulse();
    }
    if (!kIsWeb && Platform.isWindows) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
      widget.controller.addListener(_onController);
      // Defer tray until after first frame — avoids native AV during startup.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          if (mounted) unawaited(_initTray());
        });
      });
    }
  }

  void _scheduleAndroidPresencePulse() {
    _androidPresencePulse?.cancel();
    if (!Platform.isAndroid) return;
    if (!widget.controller.backgroundPresenceEnabled) return;
    final minutes = widget.controller.backgroundPresenceMinutes;
    _androidPresencePulse = Timer.periodic(
      Duration(minutes: minutes),
      (_) => unawaited(widget.controller.pulseNetworkPresence()),
    );
    unawaited(widget.controller.pulseNetworkPresence());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      unawaited(widget.controller.pulseNetworkPresence());
    }
  }

  Future<void> _initTray() async {
    if (_trayReady) return;
    try {
      trayManager.addListener(this);
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('HomeShare');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Открыть'),
            MenuItem(key: 'quit', label: 'Выход'),
          ],
        ),
      );
      _trayReady = true;
    } catch (e, st) {
      debugPrint('HomeShare tray init failed: $e\n$st');
    }
  }

  void _onController() {
    if (!mounted) return;
    final pending = widget.controller.pendingSendPaths;
    if (pending.isNotEmpty) {
      setState(() {
        _sharePaths = <String>{..._sharePaths, ...pending}.toList();
      });
      widget.controller.clearPendingSendPaths();
      return;
    }
    setState(() {});
    _scheduleTrayProgress();
  }

  Timer? _trayThrottle;
  int? _lastTrayPct;

  void _scheduleTrayProgress() {
    _trayThrottle?.cancel();
    _trayThrottle = Timer(const Duration(milliseconds: 500), () {
      unawaited(_updateTrayProgress());
    });
  }

  Future<void> _updateTrayProgress() async {
    if (kIsWeb || !Platform.isWindows || !_trayReady) return;
    final pct = widget.controller.activeProgressPercent;
    if (pct == _lastTrayPct) return;
    _lastTrayPct = pct;
    try {
      // Avoid windowManager.setProgressBar — correlated with ACCESS_VIOLATION.
      if (pct != null) {
        await trayManager.setToolTip('HomeShare $pct%');
      } else {
        await trayManager.setToolTip('HomeShare');
      }
    } catch (e) {
      debugPrint('HomeShare tray progress update failed: $e');
    }
  }

  @override
  void dispose() {
    _trayThrottle?.cancel();
    _androidPresencePulse?.cancel();
    _windowSaver.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && Platform.isWindows) {
      widget.controller.removeListener(_onController);
      windowManager.removeListener(this);
      if (_trayReady) {
        trayManager.removeListener(this);
      }
    }
    if (!kIsWeb && Platform.isAndroid) {
      widget.controller.removeListener(_onController);
    }
    super.dispose();
  }

  @override
  void onWindowMoved() => _windowSaver.scheduleSave();

  @override
  void onWindowResized() => _windowSaver.scheduleSave();

  @override
  void onWindowMaximize() => _windowSaver.scheduleSave();

  @override
  void onWindowUnmaximize() => _windowSaver.scheduleSave();

  @override
  void onWindowClose() async {
    try {
      _windowSaver.scheduleSave();
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    } catch (_) {}
  }

  Future<void> _showMainWindow() async {
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showMainWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    try {
      trayManager.popUpContextMenu();
    } catch (_) {}
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show') {
      await _showMainWindow();
    } else if (menuItem.key == 'quit') {
      await widget.controller.shutdown();
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _sharePaths.isNotEmpty
          ? PeerPickerScreen(
              controller: widget.controller,
              paths: _sharePaths,
              onDone: () {
                if (!mounted) return;
                setState(() => _sharePaths = const []);
              },
            )
          : HomeShell(controller: widget.controller),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DevicesScreen(controller: widget.controller),
      TransfersScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
    ];
    final pct = widget.controller.activeProgressPercent;
    final errors = widget.controller.recentErrors;
    return Scaffold(
      appBar: AppBar(
        title: Text(pct != null ? 'HomeShare · $pct%' : 'HomeShare'),
      ),
      body: Column(
        children: [
          if (!widget.controller.p2pRunning && errors.isNotEmpty)
            MaterialBanner(
              content: Text(errors.first),
              actions: [
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('OK'),
                ),
              ],
            ),
          Expanded(child: pages[_index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.devices),
            label: 'Устройства',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_vert),
            label: 'Передачи',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
