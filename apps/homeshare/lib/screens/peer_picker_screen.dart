import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/app_controller.dart';
import '../widgets/transfer_progress_body.dart';

/// Shown when launching via Explorer / Share with files but no --target.
class PeerPickerScreen extends StatelessWidget {
  const PeerPickerScreen({
    super.key,
    required this.controller,
    required this.paths,
    this.onDone,
  });

  final AppController controller;
  final List<String> paths;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final peers = controller.peers;
    final names = paths.map(p.basename).join(', ');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кому отправить'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => onDone?.call(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Файлы (${paths.length}): $names',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: peers.isEmpty
                ? const Center(
                    child: Text('Нет устройств. Сначала привяжите peer.'),
                  )
                : ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (context, i) {
                      final peer = peers[i];
                      return ListTile(
                        enabled: peer.host != null,
                        leading: Icon(
                          Icons.send,
                          color: peer.online ? Colors.green : Colors.grey,
                        ),
                        title: Text(peer.label, textAlign: TextAlign.center),
                        subtitle: Text(
                          peer.online ? 'онлайн' : 'офлайн',
                          textAlign: TextAlign.center,
                        ),
                        onTap: () async {
                          final jobs = await controller.sendPaths(
                            paths,
                            peerId: peer.peerId.value,
                          );
                          if (!context.mounted) return;
                          if (jobs.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Не удалось поставить в очередь'),
                              ),
                            );
                            return;
                          }
                          await showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => TransferProgressDialog(
                              controller: controller,
                              jobIds: jobs.map((j) => j.id).toList(),
                            ),
                          );
                          onDone?.call();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class TransferProgressDialog extends StatefulWidget {
  const TransferProgressDialog({
    super.key,
    required this.controller,
    required this.jobIds,
  });

  final AppController controller;
  final List<String> jobIds;

  @override
  State<TransferProgressDialog> createState() => _TransferProgressDialogState();
}

class _TransferProgressDialogState extends State<TransferProgressDialog> {
  var _closing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (!mounted || _closing) return;
    setState(() {});
    final jobs = widget.controller.jobs
        .where((j) => widget.jobIds.contains(j.id))
        .toList();
    if (jobs.isEmpty) return;
    if (jobs.every((j) => j.isTerminal)) {
      _closing = true;
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobs = widget.controller.jobs
        .where((j) => widget.jobIds.contains(j.id))
        .toList();
    final allDone = jobs.isNotEmpty && jobs.every((j) => j.isTerminal);

    return AlertDialog(
      content: SizedBox(
        width: 360,
        child: TransferProgressBody(jobs: jobs),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (allDone)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
      ],
    );
  }
}
