import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/engine_provider.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../downloads/download_tile.dart';
import '../downloads/downloads_provider.dart';
import 'preview_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _urlController = TextEditingController();
  var _dragging = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Browsers deliver dragged links as .webloc (macOS) or .url (Windows)
  /// files; extract the address and fetch its preview.
  Future<void> _handleDrop(DropDoneDetails details) async {
    for (final item in details.files) {
      final path = item.path;
      String? url;
      if (path.endsWith('.webloc') || path.endsWith('.url')) {
        final content = await File(path).readAsString();
        url = RegExp(r'https?://[^\s<>"]+').firstMatch(content)?.group(0);
      } else if (RegExp(r'^https?://').hasMatch(path)) {
        url = path;
      }
      if (url != null) {
        _urlController.text = url;
        _fetch(url);
        return;
      }
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _urlController.text = text;
    _fetch(text);
  }

  void _fetch(String value) {
    final url = value.trim();
    if (url.isEmpty) return;
    if (!url.contains('.') || url.contains(' ')) {
      ref.read(previewProvider.notifier).rejectInput();
      return;
    }
    final normalized = url.startsWith('http') ? url : 'https://$url';
    ref.read(previewProvider.notifier).fetch(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tasks = ref.watch(downloadsProvider);
    final active = tasks.where((t) => t.status.isActive).toList();
    final history = tasks.where((t) => !t.status.isActive).toList();

    return FScaffold(
      childPad: false,
      header: FHeader(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FLucideIcons.hardDriveDownload, size: 26, color: theme.colors.primary),
            const SizedBox(width: 10),
            const Text('Downpour'),
          ],
        ),
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.settings),
            onPress: () => context.go('/settings'),
          ),
        ],
      ),
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          _handleDrop(details);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              width: 2,
              color: _dragging ? theme.colors.primary : const Color(0x00000000),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    const _EngineBanner(),
                    Row(
                      children: [
                        Expanded(
                          child: FTextField(
                            control: FTextFieldControl.managed(controller: _urlController),
                            hint: 'Paste or drop a video link from YouTube, Vimeo, X, and 1800+ other sites',
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.go,
                            onSubmit: _fetch,
                            autofocus: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FButton(
                          mainAxisSize: MainAxisSize.min,
                          onPress: _paste,
                          prefix: const Icon(FLucideIcons.clipboardPaste),
                          child: const Text('Paste'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const _PreviewCard(),
                    Expanded(
                      child: tasks.isEmpty
                          ? const _EmptyState()
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 24),
                              children: [
                                if (active.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _sectionHeader(theme, 'In progress'),
                                  const SizedBox(height: 8),
                                  for (final task in active) ...[
                                    DownloadTile(key: ValueKey(task.id), task: task),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                                if (history.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _sectionHeader(theme, 'History'),
                                      const Spacer(),
                                      FButton(
                                        variant: FButtonVariant.ghost,
                                        size: FButtonSizeVariant.sm,
                                        mainAxisSize: MainAxisSize.min,
                                        onPress: () =>
                                            ref.read(downloadsProvider.notifier).clearFinished(),
                                        child: const Text('Clear history'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  for (final task in history) ...[
                                    DownloadTile(key: ValueKey(task.id), task: task),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(FThemeData theme, String text) => Text(
        text,
        style: theme.typography.body.lg.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colors.foreground,
        ),
      );
}

/// Fetched metadata for the pasted link: thumbnail, title, duration, and the
/// quality picker. Downloading only starts from here.
class _PreviewCard extends ConsumerStatefulWidget {
  const _PreviewCard();

  @override
  ConsumerState<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends ConsumerState<_PreviewCard> {
  QualityPreset? _preset;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final preview = ref.watch(previewProvider);
    final QualityPreset selected =
        _preset ?? ref.watch(settingsProvider.select((s) => s.defaultPreset));

    final Widget? content = switch (preview) {
      AsyncLoading() => Row(
          children: [
            const FCircularProgress.loader(),
            const SizedBox(width: 10),
            Text(
              'Fetching video details…',
              style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
            ),
          ],
        ),
      AsyncError(:final error) => Row(
          children: [
            Icon(FLucideIcons.circleX, size: 16, color: theme.colors.destructive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$error',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
              ),
            ),
            FButton(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              mainAxisSize: MainAxisSize.min,
              onPress: () => ref.read(previewProvider.notifier).clear(),
              child: const Icon(FLucideIcons.x, size: 14),
            ),
          ],
        ),
      AsyncData(:final value?) => _details(theme, value, selected),
      _ => null,
    };

    if (content == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FCard.raw(
        child: Padding(padding: const EdgeInsets.all(14), child: content),
      ),
    );
  }

  Widget _details(FThemeData theme, VideoInfo info, QualityPreset selected) {
    final muted = theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: info.thumbnail == null
                  ? Container(
                      width: 168,
                      height: 94,
                      color: theme.colors.secondary,
                      child: Icon(FLucideIcons.film, size: 28, color: theme.colors.mutedForeground),
                    )
                  : Image.network(
                      info.thumbnail!,
                      width: 168,
                      height: 94,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 168,
                        height: 94,
                        color: theme.colors.secondary,
                        child: Icon(FLucideIcons.film, size: 28, color: theme.colors.mutedForeground),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body.md.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (info.uploader != null) info.uploader!,
                      if (info.durationSeconds != null) formatDuration(info.durationSeconds),
                    ].join('  ·  '),
                    style: muted,
                  ),
                ],
              ),
            ),
            FButton(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              mainAxisSize: MainAxisSize.min,
              semanticsLabel: 'Dismiss preview',
              onPress: () => ref.read(previewProvider.notifier).clear(),
              child: const Icon(FLucideIcons.x, size: 14),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final preset in QualityPreset.values) ...[
              FButton(
                variant: selected == preset ? FButtonVariant.primary : FButtonVariant.outline,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: () => setState(() => _preset = preset),
                child: Text(preset.label),
              ),
              const SizedBox(width: 8),
            ],
            const Spacer(),
            FButton(
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.download),
              onPress: () {
                ref.read(downloadsProvider.notifier).enqueue(
                      info.webpageUrl,
                      selected,
                      info: info,
                    );
                ref.read(previewProvider.notifier).clear();
              },
              child: const Text('Download'),
            ),
          ],
        ),
      ],
    );
  }
}

/// First-launch engine setup progress and failure states. Invisible once the
/// engine is ready.
class _EngineBanner extends ConsumerWidget {
  const _EngineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final engine = ref.watch(engineProvider);
    final setup = ref.watch(engineSetupProgressProvider);

    final Widget? content = switch (engine) {
      AsyncError(:final error) => Row(
          children: [
            Icon(FLucideIcons.circleX, size: 16, color: theme.colors.destructive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Could not set up the download engine: $error',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
              ),
            ),
            const SizedBox(width: 8),
            FButton(
              variant: FButtonVariant.outline,
              size: FButtonSizeVariant.sm,
              mainAxisSize: MainAxisSize.min,
              onPress: () => ref.read(engineProvider.notifier).retry(),
              prefix: const Icon(FLucideIcons.refreshCw),
              child: const Text('Retry'),
            ),
          ],
        ),
      AsyncLoading() when setup != null => Row(
          children: [
            Icon(FLucideIcons.hardDriveDownload, size: 16, color: theme.colors.primary),
            const SizedBox(width: 8),
            Text(
              'One-time setup: ${setup.label}',
              style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: setup.fraction == null
                  ? const FProgress()
                  : FDeterminateProgress(value: setup.fraction!),
            ),
          ],
        ),
      _ => null,
    };

    if (content == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FCard.raw(
        child: Padding(padding: const EdgeInsets.all(12), child: content),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colors.secondary,
              shape: BoxShape.circle,
            ),
            child: Icon(FLucideIcons.arrowDownToLine, size: 34, color: theme.colors.mutedForeground),
          ),
          const SizedBox(height: 16),
          Text(
            'No downloads yet',
            style: theme.typography.body.lg.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colors.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Paste a link above to see the video details.',
            style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
