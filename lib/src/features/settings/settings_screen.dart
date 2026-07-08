import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/engine_manager.dart';
import '../../core/engine_provider.dart';
import '../../core/models.dart';
import '../../core/settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final downloadDir = ref.watch(downloadDirProvider);
    final engine = ref.watch(engineProvider);
    final setup = ref.watch(engineSetupProgressProvider);

    return FScaffold(
      header: FHeader.nested(
        title: const Text('Settings'),
        prefixes: [
          FHeaderAction.back(onPress: () => context.go('/')),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _SectionLabel('Downloads'),
              FCard.raw(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Save to', style: _labelStyle(theme)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              downloadDir.value ?? '…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FButton(
                            variant: FButtonVariant.outline,
                            size: FButtonSizeVariant.sm,
                            mainAxisSize: MainAxisSize.min,
                            prefix: const Icon(FLucideIcons.folderOpen),
                            onPress: () async {
                              final dir = await FilePicker.getDirectoryPath();
                              if (dir != null) await notifier.setDownloadDir(dir);
                            },
                            child: const Text('Choose…'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Default quality', style: _labelStyle(theme)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final preset in QualityPreset.values) ...[
                            FButton(
                              variant: settings.defaultPreset == preset
                                  ? FButtonVariant.primary
                                  : FButtonVariant.outline,
                              size: FButtonSizeVariant.sm,
                              mainAxisSize: MainAxisSize.min,
                              onPress: () => notifier.setDefaultPreset(preset),
                              child: Text(preset.label),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Format', style: _labelStyle(theme)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final container in ContainerPreference.values) ...[
                            FButton(
                              variant: settings.container == container
                                  ? FButtonVariant.primary
                                  : FButtonVariant.outline,
                              size: FButtonSizeVariant.sm,
                              mainAxisSize: MainAxisSize.min,
                              onPress: () => notifier.setContainer(container),
                              child: Text(container.label),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'MP4 uses H.264, which most sites only offer up to 1080p. '
                        'Best quality picks the highest fidelity streams, usually WebM.',
                        style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _SectionLabel('Engine'),
              FCard.raw(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      switch (engine) {
                        AsyncData(:final value) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _EngineStatus(
                                icon: FLucideIcons.circleCheck,
                                color: theme.colors.primary,
                                text: 'yt-dlp ${value.ytdlpVersion} '
                                    '(${_sourceLabel(value.ytdlpSource)}) · ${value.ytdlpPath}',
                              ),
                              const SizedBox(height: 6),
                              _EngineStatus(
                                icon: value.ffmpegAvailable
                                    ? FLucideIcons.circleCheck
                                    : FLucideIcons.circleX,
                                color: value.ffmpegAvailable
                                    ? theme.colors.primary
                                    : theme.colors.destructive,
                                text: value.ffmpegAvailable
                                    ? 'ffmpeg · ${value.ffmpegPath}'
                                    : 'ffmpeg unavailable. Downloads fall back to '
                                        'single-file formats and audio saves as M4A.',
                              ),
                              const SizedBox(height: 10),
                              const _EngineUpdateRow(),
                            ],
                          ),
                        AsyncError(:final error) => Row(
                            children: [
                              Expanded(
                                child: _EngineStatus(
                                  icon: FLucideIcons.circleX,
                                  color: theme.colors.destructive,
                                  text: '$error',
                                ),
                              ),
                              FButton(
                                variant: FButtonVariant.outline,
                                size: FButtonSizeVariant.sm,
                                mainAxisSize: MainAxisSize.min,
                                onPress: () => ref.read(engineProvider.notifier).retry(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        _ => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const FCircularProgress.loader(size: FCircularProgressSizeVariant.sm),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      setup?.label ?? 'Setting up engine…',
                                      style: theme.typography.body.xs
                                          .copyWith(color: theme.colors.mutedForeground),
                                    ),
                                  ),
                                ],
                              ),
                              if (setup?.fraction != null) ...[
                                const SizedBox(height: 8),
                                FDeterminateProgress(value: setup!.fraction!),
                              ],
                            ],
                          ),
                      },
                      const SizedBox(height: 16),
                      Text('Custom yt-dlp path (advanced, optional)', style: _labelStyle(theme)),
                      const SizedBox(height: 6),
                      FTextField(
                        control: FTextFieldControl.managed(
                          initial: TextEditingValue(text: settings.ytdlpPath ?? ''),
                        ),
                        hint: 'Managed automatically when empty',
                        onSubmit: notifier.setYtdlpPath,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _SectionLabel('About'),
              FCard.raw(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(FLucideIcons.hardDriveDownload, size: 18, color: theme.colors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Downpour',
                            style: theme.typography.body.md.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colors.foreground,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('0.1.0', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Free, open-source video downloader powered by yt-dlp and ffmpeg. '
                        'Only download content you have the right to save.',
                        style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final (label, url) in [
                            ('Downpour on GitHub', 'https://github.com/0xharkirat/downpour'),
                            ('yt-dlp', 'https://github.com/yt-dlp/yt-dlp'),
                            ('ffmpeg', 'https://ffmpeg.org'),
                          ]) ...[
                            FButton(
                              variant: FButtonVariant.outline,
                              size: FButtonSizeVariant.sm,
                              mainAxisSize: MainAxisSize.min,
                              prefix: const Icon(FLucideIcons.externalLink),
                              onPress: () => launchUrl(Uri.parse(url)),
                              child: Text(label),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _SectionLabel('Appearance'),
              FCard.raw(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      for (final (mode, label, icon) in [
                        (ThemeMode.system, 'System', FLucideIcons.monitor),
                        (ThemeMode.light, 'Light', FLucideIcons.sun),
                        (ThemeMode.dark, 'Dark', FLucideIcons.moon),
                      ]) ...[
                        FButton(
                          variant: settings.themeMode == mode
                              ? FButtonVariant.primary
                              : FButtonVariant.outline,
                          size: FButtonSizeVariant.sm,
                          mainAxisSize: MainAxisSize.min,
                          prefix: Icon(icon),
                          onPress: () => notifier.setThemeMode(mode),
                          child: Text(label),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _labelStyle(FThemeData theme) => theme.typography.body.sm.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colors.foreground,
      );

  String _sourceLabel(BinarySource source) => switch (source) {
        BinarySource.managed => 'managed by Downpour',
        BinarySource.bundled => 'bundled with Downpour',
        BinarySource.system => 'system install',
        BinarySource.custom => 'custom path',
      };
}

/// Check-for-updates flow: only offers a download when a newer yt-dlp
/// release exists, and shows when the engine was last updated.
class _EngineUpdateRow extends ConsumerWidget {
  const _EngineUpdateRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final update = ref.watch(engineUpdateProvider);
    final notifier = ref.read(engineUpdateProvider.notifier);
    final muted = theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground);

    final Widget status = switch (update.phase) {
      EngineUpdatePhase.checking => Row(
          children: [
            const FCircularProgress.loader(size: FCircularProgressSizeVariant.sm),
            const SizedBox(width: 6),
            Text('Checking for updates…', style: muted),
          ],
        ),
      EngineUpdatePhase.installing => Row(
          children: [
            const FCircularProgress.loader(size: FCircularProgressSizeVariant.sm),
            const SizedBox(width: 6),
            Text('Installing…', style: muted),
          ],
        ),
      EngineUpdatePhase.upToDate => Row(
          children: [
            Icon(FLucideIcons.circleCheck, size: 14, color: theme.colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                update.message ?? "You're up to date (${update.latestVersion}).",
                style: muted,
              ),
            ),
          ],
        ),
      EngineUpdatePhase.updateAvailable => Row(
          children: [
            Icon(FLucideIcons.hardDriveDownload, size: 14, color: theme.colors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(update.message ?? '', style: muted)),
          ],
        ),
      EngineUpdatePhase.error => Row(
          children: [
            Icon(FLucideIcons.circleX, size: 14, color: theme.colors.destructive),
            const SizedBox(width: 6),
            Expanded(child: Text(update.message ?? 'Update check failed', style: muted)),
          ],
        ),
      EngineUpdatePhase.idle => Text(
          update.lastUpdated == null
              ? 'Check for updates if downloads fail or quality drops.'
              : 'Engine last updated ${_formatDate(update.lastUpdated!)}.',
          style: muted,
        ),
    };

    final busy = update.phase == EngineUpdatePhase.checking ||
        update.phase == EngineUpdatePhase.installing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        status,
        const SizedBox(height: 8),
        Row(
          children: [
            FButton(
              variant: FButtonVariant.outline,
              size: FButtonSizeVariant.sm,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.refreshCw),
              onPress: busy ? null : notifier.checkForUpdates,
              child: const Text('Check for updates'),
            ),
            if (update.phase == EngineUpdatePhase.updateAvailable) ...[
              const SizedBox(width: 8),
              FButton(
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                prefix: const Icon(FLucideIcons.download),
                onPress: busy ? null : notifier.install,
                child: Text('Install ${update.latestVersion}'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        text.toUpperCase(),
        style: theme.typography.body.xs.copyWith(
          color: theme.colors.mutedForeground,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _EngineStatus extends StatelessWidget {
  const _EngineStatus({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground),
          ),
        ),
      ],
    );
  }
}
