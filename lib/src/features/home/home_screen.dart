import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../downloads/download_tile.dart';
import '../downloads/downloads_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _urlController = TextEditingController();
  QualityPreset? _preset;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  QualityPreset get _effectivePreset =>
      _preset ?? ref.read(settingsProvider).defaultPreset;

  Future<void> _pasteAndDownload() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _urlController.text = text;
    _submit(text);
  }

  void _submit(String value) {
    final url = value.trim();
    if (url.isEmpty || !url.contains('.')) return;
    final normalized = url.startsWith('http') ? url : 'https://$url';
    ref.read(downloadsProvider.notifier).enqueue(normalized, _effectivePreset);
    _urlController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tasks = ref.watch(downloadsProvider);
    final selectedPreset = _preset ?? ref.watch(settingsProvider.select((s) => s.defaultPreset));
    final hasFinished = tasks.any((t) => !t.status.isActive);

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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                FTextField(
                  control: FTextFieldControl.managed(controller: _urlController),
                  hint: 'Paste a video link — YouTube, Vimeo, X, and 1800+ sites',
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmit: _submit,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final preset in QualityPreset.values) ...[
                      FButton(
                        variant: selectedPreset == preset ? FButtonVariant.primary : FButtonVariant.outline,
                        size: FButtonSizeVariant.sm,
                        mainAxisSize: MainAxisSize.min,
                        onPress: () => setState(() => _preset = preset),
                        child: Text(preset.label),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Spacer(),
                    FButton(
                      size: FButtonSizeVariant.sm,
                      mainAxisSize: MainAxisSize.min,
                      onPress: _pasteAndDownload,
                      prefix: const Icon(FLucideIcons.clipboardPaste),
                      child: const Text('Paste & download'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: tasks.isEmpty
                      ? const _EmptyState()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text('Downloads', style: theme.typography.body.lg.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colors.foreground,
                                )),
                                const Spacer(),
                                if (hasFinished)
                                  FButton(
                                    variant: FButtonVariant.ghost,
                                    size: FButtonSizeVariant.sm,
                                    mainAxisSize: MainAxisSize.min,
                                    onPress: () => ref.read(downloadsProvider.notifier).clearFinished(),
                                    child: const Text('Clear finished'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.only(bottom: 24),
                                itemCount: tasks.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) => DownloadTile(
                                  key: ValueKey(tasks[index].id),
                                  task: tasks[index],
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
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
            'Paste a link above and press Enter to start.',
            style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
