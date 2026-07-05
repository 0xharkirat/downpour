import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import 'downloads_provider.dart';

class DownloadTile extends ConsumerWidget {
  const DownloadTile({required this.task, super.key});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final notifier = ref.read(downloadsProvider.notifier);

    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(task: task),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body.md.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _SubtitleLine(task: task),
                  if (task.status == DownloadStatus.downloading) ...[
                    const SizedBox(height: 10),
                    FDeterminateProgress(value: task.progress ?? 0),
                  ] else if (task.status == DownloadStatus.starting ||
                      task.status == DownloadStatus.processing) ...[
                    const SizedBox(height: 10),
                    const FProgress(),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Actions(task: task, notifier: notifier),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final thumbnail = task.info?.thumbnail;
    final placeholder = Container(
      width: 104,
      height: 58,
      color: theme.colors.secondary,
      child: Icon(
        task.preset == QualityPreset.audio ? FLucideIcons.music : FLucideIcons.film,
        size: 22,
        color: theme.colors.mutedForeground,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: thumbnail == null
          ? placeholder
          : Image.network(
              thumbnail,
              width: 104,
              height: 58,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

class _SubtitleLine extends StatelessWidget {
  const _SubtitleLine({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final muted = theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);

    final text = switch (task.status) {
      DownloadStatus.fetching => 'Fetching info…',
      DownloadStatus.starting => 'Starting download…',
      DownloadStatus.downloading =>
        '${formatBytes(task.downloadedBytes)} of ${formatBytes(task.totalBytes)}'
            '  ·  ${formatSpeed(task.speed)}  ·  ${formatEta(task.etaSeconds)} left',
      DownloadStatus.processing => 'Processing…',
      DownloadStatus.done => _doneLine,
      DownloadStatus.error => task.error ?? 'Failed',
      DownloadStatus.canceled => 'Canceled',
    };

    final color = switch (task.status) {
      DownloadStatus.error => theme.colors.destructive,
      DownloadStatus.done => theme.colors.mutedForeground,
      _ => null,
    };

    return Row(
      children: [
        if (task.status == DownloadStatus.done) ...[
          Icon(FLucideIcons.circleCheck, size: 14, color: theme.colors.primary),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: color == null ? muted : muted.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  String get _doneLine {
    final parts = [
      // The real downloaded quality beats the requested preset when known.
      task.resolution ?? task.preset.label,
      if (task.info?.uploader != null) task.info!.uploader!,
      if (task.info?.durationSeconds != null) formatDuration(task.info!.durationSeconds),
    ];
    return parts.join('  ·  ');
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.task, required this.notifier});

  final DownloadTask task;
  final DownloadsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    Widget iconButton(IconData icon, VoidCallback onPress, {String? label}) => FButton(
          variant: FButtonVariant.ghost,
          size: FButtonSizeVariant.sm,
          mainAxisSize: MainAxisSize.min,
          onPress: onPress,
          semanticsLabel: label,
          child: Icon(icon, size: 16),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.status.isActive)
          iconButton(FLucideIcons.x, () => notifier.cancel(task.id), label: 'Cancel'),
        if (task.status == DownloadStatus.done && task.filePath != null) ...[
          iconButton(FLucideIcons.play, () => notifier.openFile(task), label: 'Open'),
          iconButton(FLucideIcons.folderOpen, () => notifier.revealInFolder(task), label: 'Show in folder'),
        ],
        if (task.status == DownloadStatus.done && task.recordId != null)
          iconButton(
            FLucideIcons.captions,
            () => context.go('/transcript/${task.recordId}'),
            label: 'Transcript',
          ),
        if (!task.status.isActive) ...[
          iconButton(
            FLucideIcons.refreshCw,
            () => notifier.enqueue(task.url, task.preset, info: task.info),
            label: 'Download again',
          ),
          iconButton(FLucideIcons.trash2, () => notifier.remove(task.id), label: 'Remove'),
        ],
      ],
    );
  }
}
