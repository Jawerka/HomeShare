import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:homeshare_core/homeshare_core.dart';

import '../services/app_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameCtrl;
  List<LanAddressCandidate> _lanCandidates = const [];
  var _loadingLan = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.controller.config.displayName);
    _loadLan();
  }

  Future<void> _loadLan() async {
    setState(() => _loadingLan = true);
    final list = await widget.controller.listLanCandidates();
    if (!mounted) return;
    setState(() {
      _lanCandidates = list;
      _loadingLan = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickInbox() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Папка для входящих файлов',
    );
    if (path != null) {
      await widget.controller.setInboxDir(path);
      if (mounted) setState(() {});
    }
  }

  Future<void> _onLanChanged(String? value) async {
    // null / empty sentinel = auto
    final host = (value == null || value.isEmpty) ? null : value;
    await widget.controller.setPreferredLanHost(host);
    await _loadLan();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final preferred = c.config.preferredLanHost;
    final effective = c.lanHost;

    // Dropdown value must be in items; fall back to auto if preferred vanished.
    final dropdownValue = () {
      if (preferred == null || preferred.isEmpty) return '';
      if (_lanCandidates.any((e) => e.address == preferred)) return preferred;
      return preferred; // keep selection even if temporarily offline
    }();

    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: '',
        child: Text(
          effective == null
              ? 'Авто (локальная сеть)'
              : 'Авто: $effective',
        ),
      ),
      ..._lanCandidates.map(
        (e) => DropdownMenuItem(
          value: e.address,
          child: Text(
            '${e.interfaceName}  ${e.address}'
            '${e.isPrivateRfc1918 ? '' : ' (не LAN)'}',
          ),
        ),
      ),
      if (preferred != null &&
          preferred.isNotEmpty &&
          !_lanCandidates.any((e) => e.address == preferred))
        DropdownMenuItem(
          value: preferred,
          child: Text('$preferred (нет в сети)'),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Имя устройства',
            border: OutlineInputBorder(),
          ),
          onEditingComplete: () => c.setDisplayName(_nameCtrl.text.trim()),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () => c.setDisplayName(_nameCtrl.text.trim()),
            child: const Text('Сохранить имя'),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Папка входящих'),
          subtitle: Text(c.config.inboxDir),
          trailing: IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickInbox,
          ),
        ),
        const Divider(),
        Text('Сеть для передачи', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'По умолчанию выбирается адрес вида 192.168.x.x. '
          'Если несколько сетей (Wi-Fi, VPN, виртуальные адаптеры) — укажите нужную.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (_loadingLan)
          const LinearProgressIndicator()
        else
          DropdownButtonFormField<String>(
            key: ValueKey('lan-$dropdownValue'),
            initialValue: items.any((e) => e.value == dropdownValue)
                ? dropdownValue
                : '',
            decoration: const InputDecoration(
              labelText: 'Интерфейс / IP',
              border: OutlineInputBorder(),
            ),
            items: items,
            onChanged: (v) => _onLanChanged(v),
          ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Сейчас в QR / pairing'),
          subtitle: Text(effective ?? 'не определён'),
          trailing: IconButton(
            tooltip: 'Обновить список сетей',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await c.setPreferredLanHost(c.config.preferredLanHost);
              await _loadLan();
            },
          ),
        ),
        const Divider(),
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android) ...[
          Text('Фон', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Фоновый приём'),
            subtitle: const Text(
              'Тихое уведомление, чтобы телефон оставался видимым в LAN '
              'и принимал файлы. Периодически обновляет объявление в сети.',
            ),
            value: c.backgroundPresenceEnabled,
            onChanged: (v) async {
              await c.setBackgroundPresence(enabled: v);
              if (mounted) setState(() {});
            },
          ),
          if (c.backgroundPresenceEnabled)
            DropdownButtonFormField<int>(
              initialValue: c.backgroundPresenceMinutes,
              decoration: const InputDecoration(
                labelText: 'Интервал объявления',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('Каждую 1 мин')),
                DropdownMenuItem(value: 3, child: Text('Каждые 3 мин')),
                DropdownMenuItem(value: 5, child: Text('Каждые 5 мин')),
                DropdownMenuItem(value: 15, child: Text('Каждые 15 мин')),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await c.setBackgroundPresence(enabled: true, minutes: v);
                if (mounted) setState(() {});
              },
            ),
          const Divider(),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('P2P порт'),
          subtitle: Text('${c.config.p2pPort}'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Agent (shell)'),
          subtitle: Text('127.0.0.1:${c.config.agentPort}'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Peer ID'),
          subtitle: SelectableText(c.identity.peerId),
        ),
        if (c.recentErrors.isNotEmpty) ...[
          const Divider(),
          Text('Ошибки', style: Theme.of(context).textTheme.titleMedium),
          ...c.recentErrors.take(8).map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(e, style: const TextStyle(color: Colors.red)),
                ),
              ),
        ],
      ],
    );
  }
}
