import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:homeshare_core/homeshare_core.dart';
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
import 'services/window_shell.dart';
import 'services/window_state_store.dart';
import 'theme/home_share_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  HsLog.setup(level: kDebugMode ? Level.ALL : Level.INFO);

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
      await WindowShell.applyBounds(bounds, maximized: maximized);
      if (shouldShow) {
        await WindowShell.showAndFocus();
      } else {
        await WindowShell.hideToTray();
      }
    });
  }

  final controller = AppController();
  controller.onRequestShowWindow = () async {
    if (kIsWeb || !Platform.isWindows) return;
    await WindowShell.showAndFocus();
  };

  try {
    await controller.init();
  } catch (e, st) {
    HsLog.app.severe('HomeShare init failed', e, st);
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
      await WindowShell.showAndFocus();
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
      HsLog.app.warning('HomeShare tray init failed', e, st);
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
    } catch (e, st) {
      HsLog.app.warning('HomeShare tray progress update failed', e, st);
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
      await WindowShell.hideToTray();
    } catch (e, st) {
      HsLog.app.warning('onWindowClose failed', e, st);
    }
  }

  Future<void> _showMainWindow() => WindowShell.showAndFocus();

  @override
  void onTrayIconMouseDown() {
    unawaited(_showMainWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    try {
      trayManager.popUpContextMenu();
    } catch (e, st) {
      HsLog.app.warning('Tray context menu failed', e, st);
    }
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
      theme: HomeShareTheme.light(),
      darkTheme: HomeShareTheme.dark(),
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
    final activeCount = widget.controller.activeTransferCount;
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
                  onPressed: () => widget.controller.clearRecentErrors(),
                  child: const Text('Скрыть'),
                ),
              ],
            ),
          Expanded(child: pages[_index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.devices),
            label: 'Устройства',
          ),
          NavigationDestination(
            icon: activeCount > 0
                ? Badge(
                    label: Text('$activeCount'),
                    child: const Icon(Icons.swap_vert),
                  )
                : const Icon(Icons.swap_vert),
            label: 'Передачи',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
