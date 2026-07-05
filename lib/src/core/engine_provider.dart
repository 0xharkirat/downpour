import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_manager.dart';
import 'settings.dart';
import 'ytdlp_service.dart' show YtDlpException;

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

  void retry() => ref.invalidateSelf();
}

final engineProvider = AsyncNotifierProvider<EngineNotifier, EngineStatus>(EngineNotifier.new);

enum EngineUpdatePhase { idle, checking, upToDate, updateAvailable, installing, error }

class EngineUpdateState {
  const EngineUpdateState(this.phase, {this.latestVersion, this.message, this.lastUpdated});

  final EngineUpdatePhase phase;
  final String? latestVersion;
  final String? message;

  /// When a managed engine was last installed, from preferences.
  final DateTime? lastUpdated;
}

/// Check-for-updates flow: compare the running yt-dlp against the latest
/// release, offer an install only when they differ, and remember what was
/// installed so identical versions are never downloaded twice.
class EngineUpdateNotifier extends Notifier<EngineUpdateState> {
  static const _kVersion = 'engineInstalledVersion';
  static const _kUpdatedAt = 'engineUpdatedAt';

  @override
  EngineUpdateState build() {
    final updatedAt = ref.read(sharedPreferencesProvider).getString(_kUpdatedAt);
    return EngineUpdateState(
      EngineUpdatePhase.idle,
      lastUpdated: updatedAt == null ? null : DateTime.tryParse(updatedAt),
    );
  }

  Future<void> checkForUpdates() async {
    state = EngineUpdateState(EngineUpdatePhase.checking, lastUpdated: state.lastUpdated);
    try {
      final latest = await ref.read(engineManagerProvider).latestYtdlpVersion();
      final current = ref.read(engineProvider).value?.ytdlpVersion;
      if (current == latest) {
        state = EngineUpdateState(
          EngineUpdatePhase.upToDate,
          latestVersion: latest,
          lastUpdated: state.lastUpdated,
        );
      } else {
        state = EngineUpdateState(
          EngineUpdatePhase.updateAvailable,
          latestVersion: latest,
          message: current == null
              ? 'yt-dlp $latest is available'
              : 'New version $latest available (you have $current)',
          lastUpdated: state.lastUpdated,
        );
      }
    } on YtDlpException catch (e) {
      state = EngineUpdateState(
        EngineUpdatePhase.error,
        message: e.message,
        lastUpdated: state.lastUpdated,
      );
    }
  }

  Future<void> install() async {
    state = EngineUpdateState(
      EngineUpdatePhase.installing,
      latestVersion: state.latestVersion,
      lastUpdated: state.lastUpdated,
    );
    try {
      final version = await ref.read(engineManagerProvider).installManaged(
            onProgress: (progress) =>
                ref.read(engineSetupProgressProvider.notifier).set(progress),
          );
      ref.read(engineSetupProgressProvider.notifier).set(null);
      ref.invalidate(engineProvider);

      final now = DateTime.now();
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(_kVersion, version);
      await prefs.setString(_kUpdatedAt, now.toIso8601String());

      state = EngineUpdateState(
        EngineUpdatePhase.upToDate,
        latestVersion: version,
        message: 'Updated to yt-dlp $version',
        lastUpdated: now,
      );
    } on YtDlpException catch (e) {
      ref.read(engineSetupProgressProvider.notifier).set(null);
      state = EngineUpdateState(
        EngineUpdatePhase.error,
        message: e.message,
        lastUpdated: state.lastUpdated,
      );
    }
  }
}

final engineUpdateProvider =
    NotifierProvider<EngineUpdateNotifier, EngineUpdateState>(EngineUpdateNotifier.new);
