import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:homeshare_core/homeshare_core.dart';
import 'package:homeshare_p2p/homeshare_p2p.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

import 'transfer_notifications.dart';
import 'device_profile.dart';
import 'background_presence_channel.dart';

/// Owns identity, config, P2P server, outbox and local agent HTTP.
class AppController extends ChangeNotifier {
  late AppConfig config;
  late DeviceIdentity identity;
  late TokenStore tokens;
  late OutboxQueue outbox;
  late PairingService pairing;
  late PeerServer peerServer;
  late TransferClient transferClient;
  late TransferCoordinator coordinator;
  late InboxWriter inboxWriter;
  late Directory _dataDir;
  late File _configFile;
  UdpBeacon? beacon;
  HttpServer? agentServer;
  PresenceProbe? _presence;
  Timer? _presenceTimer;
  Timer? _uiNotifyDebounce;
  Timer? _pendingSendDebounce;

  /// Paths handed off from a second process (Explorer multi-select).
  List<String> pendingSendPaths = const [];

  /// Callback so UI can show/focus the window (set from main).
  Future<void> Function()? onRequestShowWindow;

  var p2pRunning = false;

  final List<String> recentErrors = [];
  StreamSubscription<TransferJob>? _progressSub;

  int? get activeProgressPercent {
    final active = outbox
        .list(includeTerminal: false)
        .where((j) => j.state == TransferState.transferring);
    if (active.isEmpty) return null;
    return active.first.progressPercent;
  }

  List<TrustedPeer> get peers => config.trustedPeers;
  List<TransferJob> get jobs => outbox.list();

  bool get backgroundPresenceEnabled => config.backgroundPresenceEnabled;
  int get backgroundPresenceMinutes =>
      config.backgroundPresenceMinutes.clamp(1, 30);

  Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    _dataDir = Directory(p.join(support.path, 'data'));
    await _dataDir.create(recursive: true);
    _configFile = File(p.join(support.path, 'config.json'));
    final defaultInbox = Directory(p.join(support.path, 'inbox'));
    await defaultInbox.create(recursive: true);

    final profile = await DeviceProfile.load();
    final defaultName = (profile?.displayName?.trim().isNotEmpty == true)
        ? profile!.displayName!.trim()
        : Platform.localHostname;

    config = await AppConfig.load(
      _configFile,
      defaults: AppConfig(
        displayName: defaultName,
        inboxDir: defaultInbox.path,
        dataDir: _dataDir.path,
        agentPort: HomeShareProtocol.agentPort,
        preferredLanHost: profile?.preferredLanHost,
      ),
    );
    // Prefer durable profile name over hostname after reinstall.
    if (profile?.displayName != null &&
        profile!.displayName!.trim().isNotEmpty &&
        (config.displayName == Platform.localHostname ||
            config.displayName.trim().isEmpty)) {
      config.displayName = profile.displayName!.trim();
      await config.save(_configFile);
    }
    if (profile?.preferredLanHost != null &&
        (config.preferredLanHost == null ||
            config.preferredLanHost!.isEmpty)) {
      config.preferredLanHost = profile!.preferredLanHost;
      await config.save(_configFile);
    }

    identity = await DeviceIdentity.loadOrCreate(
      dataDir: _dataDir,
      displayName: config.displayName,
    );
    if (config.displayName != identity.displayName) {
      // Prefer durable / config name after reinstall.
      if (profile?.displayName != null &&
          profile!.displayName!.trim().isNotEmpty) {
        await identity.updateDisplayName(
          profile.displayName!.trim(),
          dataDir: _dataDir,
        );
        config.displayName = identity.displayName;
        await config.save(_configFile);
      } else {
        config.displayName = identity.displayName;
        await config.save(_configFile);
      }
    }
    tokens = await TokenStore.open(_dataDir);
    outbox = await OutboxQueue.open(_dataDir);
    inboxWriter = InboxWriter(inboxDir: Directory(config.inboxDir));
    pairing = PairingService(
      identity: identity,
      config: config,
      tokenStore: tokens,
    );
    peerServer = PeerServer(
      identity: identity,
      config: config,
      tokenStore: tokens,
      inboxWriter: inboxWriter,
      pairing: pairing,
      onEvent: (kind, msg) {
        if (kind == 'error') {
          recentErrors.insert(0, msg);
          if (recentErrors.length > 30) recentErrors.removeLast();
        }
        notifyListeners();
      },
      onReceiveUpdate: (session) {
        unawaited(_onInboundReceive(session));
      },
    );

    // Agent first = single-instance lock on loopback port.
    if (!kIsWeb && Platform.isWindows) {
      await _startAgent();
    }

    try {
      await peerServer.start(port: config.p2pPort);
      p2pRunning = true;
    } on SocketException catch (e) {
      recentErrors.insert(
        0,
        'P2P порт ${config.p2pPort} занят: $e. '
        'Закройте другой HomeShare или перезапустите ПК.',
      );
      p2pRunning = false;
    } catch (e) {
      recentErrors.insert(0, 'P2P start failed: $e');
      p2pRunning = false;
    }

    if (p2pRunning) {
      try {
        beacon = UdpBeacon(
          identity: identity,
          port: config.discoveryPort,
          p2pPort: config.p2pPort,
          advertisedHost: peerServer.lanHost,
          onSendError: (msg) {
            recentErrors.insert(0, 'discovery: $msg');
            if (recentErrors.length > 30) recentErrors.removeLast();
          },
        );
        await beacon!.start();
        beacon!.peers.listen((discovered) {
          for (final d in discovered) {
            final existing = config.findPeer(d.peerId.value);
            if (existing != null) {
              unawaited(
                config.upsertPeer(
                  existing.copyWith(
                    host: d.host,
                    port: d.port,
                    online: true,
                    lastSeen: d.lastSeen,
                    displayName: d.displayName,
                  ),
                ),
              );
            }
          }
          notifyListeners();
        });
      } catch (e) {
        recentErrors.insert(0, 'discovery: $e');
      }

      _presence = PresenceProbe();
      _presenceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_probePresence());
      });
      unawaited(_probePresence());
    }

    transferClient = TransferClient(identity: identity, tokenStore: tokens);
    coordinator = TransferCoordinator(
      outbox: outbox,
      client: transferClient,
      resolvePeer: (id) => config.findPeer(id.value),
      maxParallel: 1,
    );

    // Notifications must be ready before progress events.
    await TransferNotifications.instance.init();

    coordinator.start();
    _progressSub = coordinator.progress.listen((job) {
      unawaited(_notifyJob(job));
    });
    outbox.changes.listen((_) => _scheduleUiNotify());

    if (!kIsWeb && Platform.isAndroid && config.backgroundPresenceEnabled) {
      unawaited(BackgroundPresenceChannel.start());
    }

    notifyListeners();
  }

  Future<void> setBackgroundPresence({
    required bool enabled,
    int? minutes,
  }) async {
    config.backgroundPresenceEnabled = enabled;
    if (minutes != null) {
      config.backgroundPresenceMinutes = minutes.clamp(1, 30);
    }
    await config.save(_configFile);
    if (!kIsWeb && Platform.isAndroid) {
      if (enabled) {
        await BackgroundPresenceChannel.start();
        await pulseNetworkPresence();
      } else {
        await BackgroundPresenceChannel.stop();
      }
    }
    notifyListeners();
  }

  /// Re-announce on LAN and refresh peer online state (gentle wake).
  Future<void> pulseNetworkPresence() async {
    try {
      if (p2pRunning) {
        await beacon?.announce();
      }
      await _probePresence();
      await coordinator.tick();
    } catch (e) {
      debugPrint('pulseNetworkPresence: $e');
    }
  }

  final _inboundProgressAt = <String, DateTime>{};

  Future<void> _notifyJob(TransferJob job) async {
    final active = outbox.list(includeTerminal: false);
    final batch = active.isNotEmpty
        ? active
        : [job];
    final total = batch.fold<int>(0, (s, j) => s + j.totalBytes);
    final done = batch.fold<int>(0, (s, j) => s + j.transferredBytes);
    final pct = total > 0 ? ((done / total) * 100).round() : job.progressPercent;
    final idx = batch.indexWhere((j) => j.id == job.id);
    final label = batch.length > 1
        ? '${(idx < 0 ? 1 : idx + 1)}/${batch.length} · ${job.name}'
        : job.name;

    if (job.isTerminal) {
      notifyListeners();
      final isRecv = job.direction == TransferDirection.receive;
      await TransferNotifications.instance.complete(
        message: job.state == TransferState.completed
            ? (isRecv ? 'Получено: ${job.name}' : 'Доставлено: ${job.name}')
            : 'Ошибка: ${job.name}',
      );
      return;
    }
    _scheduleUiNotify();
    await TransferNotifications.instance.showProgress(
      title: job.direction == TransferDirection.receive
          ? 'Приём · $label'
          : 'Отправка · $label',
      percent: pct,
    );
  }

  Future<void> _onInboundReceive(TransferSession session) async {
    final id = session.transferId;
    if (outbox.get(id) == null) {
      await outbox.enqueue(
        id: id,
        peerId: PeerId(session.fromPeerId),
        direction: TransferDirection.receive,
        kind: session.kind,
        name: session.name,
        totalBytes: session.totalBytes,
        sha256: session.sha256,
        manifest: session.manifest,
      );
    }

    if (session.state == TransferState.completed) {
      _inboundProgressAt.remove(id);
      await outbox.ackCompleted(id);
      final job = outbox.get(id);
      if (job != null) await _notifyJob(job);
      return;
    }
    if (session.state == TransferState.failed) {
      _inboundProgressAt.remove(id);
      await outbox.markFailed(id, session.error ?? 'failed');
      final job = outbox.get(id);
      if (job != null) await _notifyJob(job);
      return;
    }

    final now = DateTime.now();
    final last = _inboundProgressAt[id];
    final due = last == null ||
        now.difference(last) >= const Duration(milliseconds: 250);
    if (!due) {
      final existing = outbox.get(id);
      if (existing != null) {
        existing.transferredBytes = session.receivedBytes;
      }
      return;
    }
    _inboundProgressAt[id] = now;
    await outbox.update(
      id,
      state: TransferState.transferring,
      transferredBytes: session.receivedBytes,
      persist: false,
    );
    final job = outbox.get(id);
    if (job != null) await _notifyJob(job);
  }

  Future<void> _probePresence() async {
    final probe = _presence;
    if (probe == null) return;
    var changed = false;
    for (final peer in List<TrustedPeer>.from(config.trustedPeers)) {
      final host = peer.host;
      if (host == null || host.isEmpty) continue;
      final health = await probe.probe(host: host, port: peer.port);
      final updated = probe.apply(peer: peer, health: health);
      if (updated.online != peer.online ||
          updated.displayName != peer.displayName ||
          updated.lastSeen != peer.lastSeen) {
        await config.upsertPeer(updated);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      // Pending sends to peers that just came online.
      unawaited(coordinator.tick());
    }
  }

  void _scheduleUiNotify() {
    _uiNotifyDebounce?.cancel();
    _uiNotifyDebounce = Timer(const Duration(milliseconds: 250), () {
      notifyListeners();
    });
  }

  Future<void> _startAgent() async {
    final router = shelf_router.Router()
      ..get('/v1/health', (_) => Response.ok('{"ok":true}'))
      ..get('/v1/peers/online', (_) {
        final online = config.trustedPeers
            .where((p) => p.online && p.host != null)
            .map(
              (p) => {
                'peer_id': p.peerId.value,
                'display_name': p.label,
                'host': p.host,
                'port': p.port,
              },
            )
            .toList();
        return Response.ok(
          jsonEncode({'peers': online}),
          headers: {'content-type': 'application/json'},
        );
      })
      ..post('/v1/send', (Request request) async {
        final body =
            jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final peerId = body['peer_id'] as String;
        final paths =
            (body['paths'] as List).map((e) => e as String).toList();
        await sendPaths(paths, peerId: peerId);
        return Response.ok(jsonEncode({'ok': true}));
      })
      ..post('/v1/invoke', (Request request) async {
        final body =
            jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final paths = (body['paths'] as List? ?? const [])
            .map((e) => e as String)
            .where((e) => e.isNotEmpty)
            .toList();
        final peerId = body['peer_id'] as String?;
        final show = body['show'] as bool? ?? true;
        if (show) {
          unawaited(onRequestShowWindow?.call() ?? Future<void>.value());
        }
        if (paths.isEmpty) {
          return Response.ok(jsonEncode({'ok': true, 'action': 'show'}));
        }
        if (peerId != null && peerId.isNotEmpty) {
          await sendPaths(paths, peerId: peerId);
          return Response.ok(jsonEncode({'ok': true, 'action': 'send'}));
        }
        // Merge paths from multiple Explorer invocations (multi-select).
        queuePendingSendPaths(paths);
        return Response.ok(jsonEncode({'ok': true, 'action': 'picker'}));
      });

    try {
      agentServer = await shelf_io.serve(
        router.call,
        InternetAddress.loopbackIPv4,
        config.agentPort,
      );
    } on SocketException catch (e) {
      throw StateError(
        'Agent port ${config.agentPort} busy (another HomeShare?). $e',
      );
    }
  }

  /// Collect paths from CLI / Explorer; debounce so multi-select handoffs merge.
  void queuePendingSendPaths(List<String> paths) {
    if (paths.isEmpty) return;
    pendingSendPaths = <String>{...pendingSendPaths, ...paths}.toList();
    _pendingSendDebounce?.cancel();
    _pendingSendDebounce = Timer(const Duration(milliseconds: 450), () {
      notifyListeners();
    });
  }

  void clearPendingSendPaths() {
    _pendingSendDebounce?.cancel();
    _pendingSendDebounce = null;
    pendingSendPaths = const [];
    notifyListeners();
  }

  Future<void> pairWithPin({
    required String host,
    required int port,
    required String pin,
  }) async {
    await pairing.confirmAsGuest(host: host, port: port, pin: pin);
    notifyListeners();
  }

  Future<void> revokePeer(String peerId) async {
    await config.revokePeer(peerId);
    await tokens.remove(peerId);
    notifyListeners();
  }

  Future<void> setPeerAlias(String peerId, String? alias) async {
    final peer = config.findPeer(peerId);
    if (peer == null) return;
    final trimmed = alias?.trim();
    await config.upsertPeer(
      peer.copyWith(
        alias: trimmed,
        clearAlias: trimmed == null || trimmed.isEmpty,
      ),
    );
    notifyListeners();
  }

  Future<void> setInboxDir(String path) async {
    config.inboxDir = path;
    await config.save(_configFile);
    inboxWriter = InboxWriter(inboxDir: Directory(path));
    notifyListeners();
  }

  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    config.displayName = trimmed;
    await config.save(_configFile);
    await identity.updateDisplayName(trimmed, dataDir: _dataDir);
    beacon?.identity = identity;
    await beacon?.announce();
    await DeviceProfile(
      displayName: trimmed,
      preferredLanHost: config.preferredLanHost,
    ).save();
    notifyListeners();
  }

  Future<void> setPreferredLanHost(String? host) async {
    final trimmed = host?.trim();
    config.preferredLanHost =
        (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    await config.save(_configFile);
    await DeviceProfile(
      displayName: config.displayName,
      preferredLanHost: config.preferredLanHost,
    ).save();
    if (p2pRunning) {
      await peerServer.refreshLanHost();
      await beacon?.setAdvertisedHost(peerServer.lanHost);
    }
    notifyListeners();
  }

  Future<List<LanAddressCandidate>> listLanCandidates() =>
      LanAddress.listCandidates();

  String? get lanHost => peerServer.lanHost;

  Future<List<TransferJob>> sendPaths(
    List<String> paths, {
    required String peerId,
  }) async {
    final peer = config.findPeer(peerId);
    if (peer == null) {
      recentErrors.insert(0, 'peer not found');
      notifyListeners();
      return const [];
    }
    final unique = <String>{...paths}.toList();
    final jobs = <TransferJob>[];
    for (final path in unique) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.notFound) {
        recentErrors.insert(0, 'not found: $path');
        continue;
      }
      if (type == FileSystemEntityType.directory) {
        jobs.add(
          await coordinator.enqueueDirectory(
            peerId: PeerId(peerId),
            directory: Directory(path),
          ),
        );
      } else {
        jobs.add(
          await coordinator.enqueueFile(
            peerId: PeerId(peerId),
            file: File(path),
          ),
        );
      }
    }
    await coordinator.tick();
    notifyListeners();
    return jobs;
  }

  Map<String, Object?> pairingOfferJson() =>
      pairing.offerJson(lanHost: peerServer.lanHost);

  Future<void> shutdown() async {
    _presenceTimer?.cancel();
    _uiNotifyDebounce?.cancel();
    _pendingSendDebounce?.cancel();
    _presence?.close();
    await _progressSub?.cancel();
    coordinator.stop();
    await beacon?.stop();
    await peerServer.stop();
    await agentServer?.close(force: true);
    transferClient.close();
    await outbox.close();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
