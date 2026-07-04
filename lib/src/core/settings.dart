import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'ytdlp_service.dart';

/// Overridden in main() with the real instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final ytDlpServiceProvider = Provider<YtDlpService>((_) => YtDlpService());

class AppSettings {
  const AppSettings({
    this.downloadDir,
    this.ytdlpPath,
    this.defaultPreset = QualityPreset.best,
    this.themeMode = ThemeMode.system,
  });

  final String? downloadDir;
  final String? ytdlpPath;
  final QualityPreset defaultPreset;
  final ThemeMode themeMode;

  AppSettings copyWith({
    String? downloadDir,
    String? ytdlpPath,
    QualityPreset? defaultPreset,
    ThemeMode? themeMode,
  }) =>
      AppSettings(
        downloadDir: downloadDir ?? this.downloadDir,
        ytdlpPath: ytdlpPath ?? this.ytdlpPath,
        defaultPreset: defaultPreset ?? this.defaultPreset,
        themeMode: themeMode ?? this.themeMode,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _kDownloadDir = 'downloadDir';
  static const _kYtdlpPath = 'ytdlpPath';
  static const _kPreset = 'defaultPreset';
  static const _kThemeMode = 'themeMode';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      downloadDir: prefs.getString(_kDownloadDir),
      ytdlpPath: prefs.getString(_kYtdlpPath),
      defaultPreset: QualityPreset.values.asNameMap()[prefs.getString(_kPreset)] ?? QualityPreset.best,
      themeMode: ThemeMode.values.asNameMap()[prefs.getString(_kThemeMode)] ?? ThemeMode.system,
    );
  }

  Future<void> setDownloadDir(String dir) async {
    state = state.copyWith(downloadDir: dir);
    await _prefs.setString(_kDownloadDir, dir);
  }

  Future<void> setYtdlpPath(String path) async {
    state = state.copyWith(ytdlpPath: path);
    if (path.trim().isEmpty) {
      await _prefs.remove(_kYtdlpPath);
    } else {
      await _prefs.setString(_kYtdlpPath, path.trim());
    }
    ref.invalidate(ytDlpVersionProvider);
  }

  Future<void> setDefaultPreset(QualityPreset preset) async {
    state = state.copyWith(defaultPreset: preset);
    await _prefs.setString(_kPreset, preset.name);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_kThemeMode, mode.name);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final themeModeProvider = Provider<ThemeMode>((ref) => ref.watch(settingsProvider).themeMode);

/// Resolved download directory, falling back to the platform Downloads folder.
final downloadDirProvider = FutureProvider<String>((ref) async {
  final configured = ref.watch(settingsProvider.select((s) => s.downloadDir));
  if (configured != null && configured.isNotEmpty) return configured;
  final downloads = await getDownloadsDirectory();
  if (downloads != null) return downloads.path;
  final documents = await getApplicationDocumentsDirectory();
  return documents.path;
});

/// Resolved yt-dlp version, used as a health check on the settings screen.
final ytDlpVersionProvider = FutureProvider<String>((ref) async {
  final service = ref.watch(ytDlpServiceProvider);
  final override = ref.watch(settingsProvider.select((s) => s.ytdlpPath));
  final bin = await service.resolveBinary(override: override);
  final version = await service.version(override: override);
  return '$version · $bin';
});

/// Whether this platform can spawn the yt-dlp CLI.
final engineSupportedProvider = Provider<bool>(
  (_) => Platform.isMacOS || Platform.isWindows || Platform.isLinux,
);
