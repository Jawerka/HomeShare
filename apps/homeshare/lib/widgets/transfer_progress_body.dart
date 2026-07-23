import 'package:flutter/material.dart';
import 'package:homeshare_core/homeshare_core.dart';

/// Centered transfer progress used by Transfers tab and popup dialog.
class TransferProgressBody extends StatelessWidget {
  const TransferProgressBody({
    super.key,
    required this.jobs,
    this.compact = false,
  });

  final List<TransferJob> jobs;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return const Center(child: Text('Ожидание…'));
    }

    final totalBytes = jobs.fold<int>(0, (s, j) => s + j.totalBytes);
    final doneBytes = jobs.fold<int>(0, (s, j) {
      if (j.state == TransferState.completed) return s + j.totalBytes;
      return s + j.transferredBytes;
    });
    final completed =
        jobs.where((j) => j.state == TransferState.completed).length;
    final failed = jobs.where((j) => j.state == TransferState.failed).length;
    final overall =
        totalBytes > 0 ? (doneBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
    final allDone = jobs.every((j) => j.isTerminal);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          allDone
              ? (failed > 0 ? 'Готово с ошибками' : 'Готово')
              : 'Передача файлов',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '$completed из ${jobs.length}'
          '${failed > 0 ? ' · ошибок: $failed' : ''}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: allDone ? 1 : overall),
        const SizedBox(height: 8),
        Text(
          '${(overall * 100).round()}%',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (!compact) ...[
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: jobs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final job = jobs[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_iconFor(job), color: _colorFor(job), size: 20),
                  title: Text(
                    job.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_subtitleFor(job)),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  static IconData _iconFor(TransferJob job) {
    switch (job.state) {
      case TransferState.completed:
        return Icons.check_circle;
      case TransferState.failed:
        return Icons.error;
      case TransferState.transferring:
        return job.direction == TransferDirection.receive
            ? Icons.download
            : Icons.upload_file;
      default:
        return Icons.hourglass_empty;
    }
  }

  static Color? _colorFor(TransferJob job) {
    switch (job.state) {
      case TransferState.completed:
        return Colors.green;
      case TransferState.failed:
        return Colors.red;
      default:
        return null;
    }
  }

  static String _subtitleFor(TransferJob job) {
    switch (job.state) {
      case TransferState.completed:
        return job.direction == TransferDirection.receive
            ? 'Получено'
            : 'Готово';
      case TransferState.failed:
        return job.errorMessage ?? 'Ошибка';
      case TransferState.transferring:
        return '${job.progressPercent}%';
      case TransferState.pending:
        return 'В очереди';
      default:
        return job.state.name;
    }
  }
}
