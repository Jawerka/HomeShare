import 'dart:async';

import 'package:flutter/material.dart';
import 'package:homeshare_core/homeshare_core.dart';

import '../services/app_controller.dart';
import '../theme/home_share_theme.dart';
import '../widgets/transfer_progress_body.dart';

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final jobs = controller.jobs;
    if (jobs.isEmpty) {
      return const EmptyState(
        icon: Icons.swap_vert,
        title: 'Передач пока нет',
        subtitle: 'Отправьте файл через Share или контекстное меню Explorer',
      );
    }

    final active = jobs.where((j) => !j.isTerminal).toList();
    final recent = jobs.take(20).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (active.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: TransferProgressBody(jobs: active),
          ),
          const SizedBox(height: 8),
          Text('История', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        ...recent.map((job) {
          final terminal = job.isTerminal;
          final failed = job.state == TransferState.failed;
          final cancelled = job.state == TransferState.cancelled;
          return ListTile(
            leading: Icon(
              terminal
                  ? (job.state == TransferState.completed
                      ? Icons.check_circle
                      : Icons.error_outline)
                  : (job.direction == TransferDirection.receive
                      ? Icons.download
                      : Icons.upload),
              color: terminal
                  ? (job.state == TransferState.completed
                      ? Colors.green
                      : Colors.red)
                  : null,
            ),
            title: Text(job.name),
            subtitle: Text(
              '${job.direction == TransferDirection.receive ? 'приём' : 'отправка'}'
              ' · ${transferStateLabel(job.state)}'
              '${terminal ? '' : ' · ${job.progressPercent}%'}',
            ),
            trailing: terminal && (failed || cancelled)
                ? IconButton(
                    tooltip: 'Повторить',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => unawaited(controller.retryJob(job.id)),
                  )
                : !terminal
                    ? IconButton(
                        tooltip: 'Отменить',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            unawaited(controller.cancelJob(job.id)),
                      )
                    : null,
          );
        }),
      ],
    );
  }
}
