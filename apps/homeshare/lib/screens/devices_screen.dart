import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:homeshare_p2p/homeshare_p2p.dart';

import '../services/app_controller.dart';
import '../theme/home_share_theme.dart';

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
    final pin = '${offer['pin']}';
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
                  'Ваш PIN',
                  style: Theme.of(ctx).textTheme.labelLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  pin,
                  style: Theme.of(ctx).textTheme.displaySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 6,
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'LAN: ${offer['lan_host'] ?? '?'}:${offer['http_port']}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: pin));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('PIN скопирован')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Копировать PIN'),
                ),
                const Divider(height: 28),
                const Text('Или введите PIN другого устройства:'),
                const SizedBox(height: 8),
                TextField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'IP хоста',
                    hintText: '192.168.x.x',
                  ),
                ),
                const SizedBox(height: 8),
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

  Future<void> _confirmRevoke(String peerId, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отвязать устройство?'),
        content: Text(
          '«$label» больше не сможет обмениваться файлами без нового PIN.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отвязать'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.controller.revokePeer(peerId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peers = widget.controller.peers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: FilledButton.icon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add_link),
            label: const Text('Добавить устройство'),
          ),
        ),
        Expanded(
          child: peers.isEmpty
              ? EmptyState(
                  icon: Icons.devices_other,
                  title: 'Нет привязанных устройств',
                  subtitle: 'Привяжите устройство по PIN в локальной сети',
                  action: FilledButton(
                    onPressed: _showAddDialog,
                    child: const Text('Добавить'),
                  ),
                )
              : ListView.builder(
                  itemCount: peers.length,
                  itemBuilder: (context, i) {
                    final peer = peers[i];
                    return ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: peer.online
                            ? Colors.green
                            : Theme.of(context).colorScheme.outline,
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
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'rename') {
                            unawaited(
                              _renamePeer(peer.peerId.value, peer.label),
                            );
                          } else if (v == 'revoke') {
                            unawaited(
                              _confirmRevoke(peer.peerId.value, peer.label),
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Переименовать'),
                          ),
                          PopupMenuItem(
                            value: 'revoke',
                            child: Text('Отвязать'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
