import 'dart:io';

import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'transcript_provider.dart';

class TranscriptScreen extends ConsumerWidget {
  const TranscriptScreen({required this.recordId, super.key});

  final int recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final transcript = ref.watch(transcriptProvider(recordId));

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Transcript'),
        prefixes: [
          FHeaderAction.back(onPress: () => context.go('/')),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: switch (transcript) {
            AsyncData(:final value) => _Body(result: value),
            AsyncError(:final error) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FLucideIcons.circleX, size: 28, color: theme.colors.destructive),
                    const SizedBox(height: 10),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
                    ),
                    const SizedBox(height: 12),
                    FButton(
                      variant: FButtonVariant.outline,
                      size: FButtonSizeVariant.sm,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () => ref.invalidate(transcriptProvider(recordId)),
                      prefix: const Icon(FLucideIcons.refreshCw),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            _ => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FCircularProgress.loader(),
                    const SizedBox(height: 12),
                    Text(
                      'Fetching captions…',
                      style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
                    ),
                  ],
                ),
              ),
          },
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.result});

  final TranscriptResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final record = result.record;
    final muted = theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);

    if (result.segments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FLucideIcons.captions, size: 28, color: theme.colors.mutedForeground),
            const SizedBox(height: 10),
            Text('No captions available for this video.', style: muted),
            const SizedBox(height: 4),
            Text(
              'Local transcription (whisper.cpp) is planned for caption-less videos.',
              style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Text(
          record.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.body.lg.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colors.foreground,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FButton(
              variant: FButtonVariant.outline,
              size: FButtonSizeVariant.sm,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.externalLink),
              onPress: () => launchUrl(Uri.parse(record.url)),
              child: const Text('Watch video'),
            ),
            const SizedBox(width: 8),
            if (record.filePath != null)
              FButton(
                variant: FButtonVariant.outline,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                prefix: const Icon(FLucideIcons.folderOpen),
                onPress: () => _reveal(record.filePath!),
                child: const Text('Video file'),
              ),
            if (result.sidecarPath != null) ...[
              const SizedBox(width: 8),
              FButton(
                variant: FButtonVariant.outline,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                prefix: const Icon(FLucideIcons.fileText),
                onPress: () => _reveal(result.sidecarPath!),
                child: const Text('Transcript file'),
              ),
            ],
            const Spacer(),
            FButton(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.copy),
              onPress: () => Clipboard.setData(
                ClipboardData(
                  text: ref.read(transcriptServiceProvider).toPlainText(result.segments),
                ),
              ),
              child: const Text('Copy all'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FCard.raw(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: result.segments.length,
              itemBuilder: (context, index) {
                final segment = result.segments[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SelectionArea(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            segment.timestamp,
                            style: theme.typography.body.xs.copyWith(
                              color: theme.colors.mutedForeground,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            segment.text,
                            style: theme.typography.body.sm.copyWith(
                              color: theme.colors.foreground,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _reveal(String path) {
    if (Platform.isMacOS) {
      Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      Process.run('explorer', ['/select,', path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [File(path).parent.path]);
    }
  }
}
