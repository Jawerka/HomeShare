import 'package:flutter/material.dart';
import 'package:homeshare_p2p/homeshare_p2p.dart';

import '../services/app_controller.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _hostCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAddDialog() async {
    final offer = widget.controller.pairingOfferJson();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Добавить устройство'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ваш PIN: ${offer['pin']}',
                  style: Theme.of(ctx).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'LAN: ${offer['lan_host'] ?? '?'}:${offer['http_port']}',
                  textAlign: TextAlign.center,
                ),
                const Divider(height: 24),
                const Text('Или введите PIN другого устройства:'),
                TextField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'IP хоста',
                    hintText: '192.168.x.x',
                  ),
                ),
                TextField(
                  controller: _pinCtrl,
                  decoration: const InputDecoration(labelText: 'PIN (6 цифр)'),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть'),
            ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await widget.controller.pairWithPin(
                          host: _hostCtrl.text.trim(),
                          port: HomeShareProtocol.p2pPort,
                          pin: _pinCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Ошибка: $e')),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('Привязать'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _renamePeer(String peerId, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Имя устройства'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Локальное имя',
            hintText: 'Например: Телефон',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null) return;
    await widget.controller.setPeerAlias(peerId, name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    final peers = widget.controller.peers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Добавить устройство'),
          ),
        ),
        Expanded(
          child: peers.isEmpty
              ? const Center(child: Text('Нет привязанных устройств'))
              : ListView.builder(
                  itemCount: peers.length,
                  itemBuilder: (context, i) {
                    final peer = peers[i];
                    return ListTile(
                      leading: Icon(
                        Icons.devices,
                        color: peer.online ? Colors.green : Colors.grey,
                      ),
                      title: Text(peer.label),
                      subtitle: Text(
                        [
                          if (peer.alias != null && peer.alias!.isNotEmpty)
                            peer.displayName,
                          peer.online ? 'онлайн' : 'офлайн',
                          if (peer.host != null) peer.host!,
                        ].join(' · '),
                      ),
                      onLongPress: () => _renamePeer(peer.peerId.value, peer.label),
                      trailing: IconButton(
                        icon: const Icon(Icons.link_off),
                        tooltip: 'Отвязать',
                        onPressed: () =>
                            widget.controller.revokePeer(peer.peerId.value),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
