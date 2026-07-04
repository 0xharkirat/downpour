import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_manager.dart';
import 'settings.dart';

/// Overridden in main() with a manager rooted in the app support directory.
final engineManagerProvider = Provider<EngineManager>(
  (_) => throw UnimplementedError('engineManagerProvider must be overridden'),
);

/// Live setup progress while binaries download on first launch.
class EngineSetupProgressNotifier extends Notifier<EngineSetupProgress?> {
  @override
  EngineSetupProgress? build() => null;

  void set(EngineSetupProgress? progress) => state = progress;
}

final engineSetupProgressProvider =
    NotifierProvider<EngineSetupProgressNotifier, EngineSetupProgress?>(
  EngineSetupProgressNotifier.new,
);

class EngineNotifier extends AsyncNotifier<EngineStatus> {
  @override
  Future<EngineStatus> build() async {
    final manager = ref.watch(engineManagerProvider);
    final override = ref.watch(settingsProvider.select((s) => s.ytdlpPath));
    try {
      return await manager.ensure(
        ytdlpOverride: override,
        onProgress: (progress) =>
            ref.read(engineSetupProgressProvider.notifier).set(progress),
      );
    } finally {
      ref.read(engineSetupProgressProvider.notifier).set(null);
    }
  }

  Future<void> updateYtdlp() async {
    final current = state.value;
    if (current == null) return;
    state = const AsyncLoading<EngineStatus>();
    await ref.read(engineManagerProvider).updateYtdlp(current);
    ref.invalidateSelf();
  }

  void retry() => ref.invalidateSelf();
}

final engineProvider = AsyncNotifierProvider<EngineNotifier, EngineStatus>(EngineNotifier.new);
