import 'package:flutter/material.dart';
import 'package:homeshare_core/homeshare_core.dart';

import '../services/app_controller.dart';
import '../widgets/transfer_progress_body.dart';

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final jobs = controller.jobs;
    if (jobs.isEmpty) {
      return const Center(child: Text('Передач пока нет'));
    }

    final active = jobs.where((j) => !j.isTerminal).toList();
    final recent = jobs.take(12).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (active.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TransferProgressBody(jobs: active),
            ),
          ),
          const SizedBox(height: 16),
          Text('История', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        ...recent.map((job) {
          final terminal = job.isTerminal;
          return ListTile(
            leading: Icon(
              terminal
                  ? (job.state == TransferState.completed
                      ? Icons.check_circle
                      : Icons.error)
                  : (job.direction == TransferDirection.receive
                      ? Icons.download
                      : Icons.upload),
              color: terminal
                  ? (job.state == TransferState.completed
                      ? Colors.green
                      : Colors.red)
                  : null,
            ),
            title: Text(job.name, textAlign: TextAlign.center),
            subtitle: Text(
              '${job.direction == TransferDirection.receive ? 'приём' : 'отправка'}'
              ' · ${job.state.name}'
              '${terminal ? '' : ' · ${job.progressPercent}%'}',
              textAlign: TextAlign.center,
            ),
          );
        }),
      ],
    );
  }
}
