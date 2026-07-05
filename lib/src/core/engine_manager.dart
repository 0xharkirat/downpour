import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ytdlp_service.dart' show YtDlpException;

/// Where a binary came from.
enum BinarySource { custom, managed, bundled, system }

class EngineStatus {
  const EngineStatus({
    required this.ytdlpPath,
    required this.ytdlpSource,
    required this.ytdlpVersion,
    this.ffmpegPath,
  });

  final String ytdlpPath;
  final BinarySource ytdlpSource;
  final String ytdlpVersion;

  /// Null means merging/conversion is unavailable and presets degrade to
  /// single-file formats.
  final String? ffmpegPath;

  bool get ffmpegAvailable => ffmpegPath != null;
}

/// Setup progress reported while binaries are fetched on first launch.
class EngineSetupProgress {
  const EngineSetupProgress(this.label, [this.fraction]);

  final String label;
  final double? fraction;
}

/// Provisions yt-dlp and ffmpeg without requiring the user to install
/// anything: uses a custom path or an existing system install when present,
/// otherwise downloads official standalone builds into the app data folder.
class EngineManager {
  EngineManager({required this.dataDirectory, this.useSystemBinaries = true});

  /// Directory owned by the app where managed binaries live.
  final Directory dataDirectory;

  /// Disabled in tests to force the managed download path.
  final bool useSystemBinaries;

  static const _ytdlpDownloads = {
    'macos': 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos',
    'windows': 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe',
    'linux': 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux',
  };

  static final _ffmpegDownloads = {
    'macos': 'https://ffmpeg.martin-riedl.de/redirect/latest/macos/'
        '${_isArm ? 'arm64' : 'amd64'}/release/ffmpeg.zip',
    'windows':
        'https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip',
    'linux':
        'https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-linux64-gpl.tar.xz',
  };

  static bool get _isArm => Platform.version.contains('arm64') || Platform.version.contains('aarch64');

  static String get _os => Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
          ? 'windows'
          : 'linux';

  static String get _exe => Platform.isWindows ? '.exe' : '';

  String get _managedYtdlp => '${dataDirectory.path}${Platform.pathSeparator}yt-dlp$_exe';
  String get _managedFfmpeg => '${dataDirectory.path}${Platform.pathSeparator}ffmpeg$_exe';

  /// Binaries shipped inside the app package by tool/bundle_engine.dart.
  ///
  /// macOS: Downpour.app/Contents/Resources/engine/ (exe lives in
  /// Contents/MacOS/). Windows and Linux: engine/ next to the executable.
  static String get bundledDir {
    final exeDir = File(Platform.resolvedExecutable).parent;
    if (Platform.isMacOS) {
      return '${exeDir.parent.path}${Platform.pathSeparator}Resources'
          '${Platform.pathSeparator}engine';
    }
    return '${exeDir.path}${Platform.pathSeparator}engine';
  }

  String get _bundledYtdlp => '$bundledDir${Platform.pathSeparator}yt-dlp$_exe';
  String get _bundledFfmpeg => '$bundledDir${Platform.pathSeparator}ffmpeg$_exe';

  static List<String> get _systemCandidates {
    final home = Platform.environment['HOME'] ?? '';
    if (Platform.isWindows) {
      final appData = Platform.environment['LOCALAPPDATA'] ?? '';
      return [
        '$appData\\Microsoft\\WinGet\\Links',
        'C:\\ProgramData\\chocolatey\\bin',
      ];
    }
    return ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '$home/.local/bin', '$home/.pyenv/shims'];
  }

  /// Resolves both binaries, downloading them if needed.
  Future<EngineStatus> ensure({
    String? ytdlpOverride,
    void Function(EngineSetupProgress progress)? onProgress,
  }) async {
    await dataDirectory.create(recursive: true);

    final (ytdlp, source) = await _ensureYtdlp(ytdlpOverride, onProgress);
    final version = await _runVersion(ytdlp);
    final ffmpeg = await _ensureFfmpeg(onProgress);

    return EngineStatus(
      ytdlpPath: ytdlp,
      ytdlpSource: source,
      ytdlpVersion: version,
      ffmpegPath: ffmpeg,
    );
  }

  /// Latest yt-dlp release tag from GitHub, e.g. "2026.06.09".
  Future<String> latestYtdlpVersion() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw YtDlpException('Update check failed (HTTP ${response.statusCode})');
      }
      final body = await response.transform(utf8.decoder).join();
      final tag = (jsonDecode(body) as Map<String, dynamic>)['tag_name'] as String?;
      if (tag == null || tag.isEmpty) throw YtDlpException('Update check returned no version');
      return tag;
    } on SocketException {
      throw YtDlpException('Update check failed: no internet connection');
    } finally {
      client.close();
    }
  }

  /// Installs the latest yt-dlp into the managed directory (shadowing bundled
  /// and system copies) and provisions ffmpeg if missing. Skips the download
  /// when the managed copy is already the latest release, unless [force].
  /// Returns the installed version.
  Future<String> installManaged({
    bool force = false,
    void Function(EngineSetupProgress progress)? onProgress,
  }) async {
    await dataDirectory.create(recursive: true);

    onProgress?.call(const EngineSetupProgress('Checking latest version…'));
    final latest = await latestYtdlpVersion();

    var current = '';
    if (await File(_managedYtdlp).exists()) {
      current = await _runVersion(_managedYtdlp);
    }

    if (force || current != latest) {
      onProgress?.call(const EngineSetupProgress('Downloading yt-dlp…'));
      final temp = File('$_managedYtdlp.part');
      await _download(
        _ytdlpDownloads[_os]!,
        temp,
        (fraction) => onProgress?.call(EngineSetupProgress('Downloading yt-dlp…', fraction)),
      );
      if (await File(_managedYtdlp).exists()) await File(_managedYtdlp).delete();
      await temp.rename(_managedYtdlp);
      await _markExecutable(_managedYtdlp);
      current = await _runVersion(_managedYtdlp);
    }

    // ffmpeg builds are not versioned the same way; fetch only when absent.
    await _ensureFfmpeg(onProgress);
    return current;
  }

  Future<(String, BinarySource)> _ensureYtdlp(
    String? override,
    void Function(EngineSetupProgress)? onProgress,
  ) async {
    if (override != null && override.trim().isNotEmpty) {
      final path = override.trim();
      if (!await File(path).exists()) {
        throw YtDlpException('yt-dlp not found at $path. Clear the custom path in Settings.');
      }
      return (path, BinarySource.custom);
    }

    // Managed before bundled: in-app updates land in the managed dir and must
    // shadow the (fixed) copy shipped inside the app package.
    if (await File(_managedYtdlp).exists()) return (_managedYtdlp, BinarySource.managed);
    if (await File(_bundledYtdlp).exists()) return (_bundledYtdlp, BinarySource.bundled);

    if (useSystemBinaries) {
      final system = await _findOnSystem('yt-dlp$_exe');
      if (system != null) return (system, BinarySource.system);
    }

    onProgress?.call(const EngineSetupProgress('Downloading yt-dlp…'));
    final temp = File('$_managedYtdlp.part');
    await _download(
      _ytdlpDownloads[_os]!,
      temp,
      (fraction) => onProgress?.call(EngineSetupProgress('Downloading yt-dlp…', fraction)),
    );
    await temp.rename(_managedYtdlp);
    await _markExecutable(_managedYtdlp);

    // Fail loudly now rather than on the first download attempt.
    await _runVersion(_managedYtdlp);
    return (_managedYtdlp, BinarySource.managed);
  }

  Future<String?> _ensureFfmpeg(void Function(EngineSetupProgress)? onProgress) async {
    if (await File(_managedFfmpeg).exists()) return _managedFfmpeg;
    if (await File(_bundledFfmpeg).exists()) return _bundledFfmpeg;

    if (useSystemBinaries) {
      final system = await _findOnSystem('ffmpeg$_exe');
      if (system != null) return system;
    }

    try {
      onProgress?.call(const EngineSetupProgress('Downloading ffmpeg…'));
      final url = _ffmpegDownloads[_os]!;
      final archive = File('${dataDirectory.path}${Platform.pathSeparator}ffmpeg-archive');
      await _download(
        url,
        archive,
        (fraction) => onProgress?.call(EngineSetupProgress('Downloading ffmpeg…', fraction)),
      );

      onProgress?.call(const EngineSetupProgress('Unpacking ffmpeg…'));
      final extracted = await _extractFfmpeg(archive);
      await archive.delete();
      if (extracted == null) return null;
      await _markExecutable(_managedFfmpeg);
      return _managedFfmpeg;
    } catch (_) {
      // ffmpeg is optional: downloads still work, presets degrade to
      // single-file formats.
      return null;
    }
  }

  Future<String?> _extractFfmpeg(File archive) async {
    final extractDir = Directory('${dataDirectory.path}${Platform.pathSeparator}ffmpeg-tmp');
    if (await extractDir.exists()) await extractDir.delete(recursive: true);
    await extractDir.create(recursive: true);

    // bsdtar handles .zip, .tar.xz, and .tar.gz alike on macOS, Linux, and
    // Windows 10+.
    final result = await Process.run('tar', ['-xf', archive.path, '-C', extractDir.path]);
    if (result.exitCode != 0) {
      await extractDir.delete(recursive: true);
      return null;
    }

    File? found;
    await for (final entry in extractDir.list(recursive: true)) {
      if (entry is File) {
        final name = entry.uri.pathSegments.last;
        if (name == 'ffmpeg$_exe') {
          found = entry;
          break;
        }
      }
    }
    if (found == null) {
      await extractDir.delete(recursive: true);
      return null;
    }
    await found.copy(_managedFfmpeg);
    await extractDir.delete(recursive: true);
    return _managedFfmpeg;
  }

  Future<String?> _findOnSystem(String name) async {
    for (final dir in _systemCandidates) {
      final path = '$dir${Platform.pathSeparator}$name';
      if (await File(path).exists()) return path;
    }
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('where', [name]);
      } else {
        final shell = Platform.environment['SHELL'] ?? '/bin/sh';
        result = await Process.run(shell, ['-lc', 'command -v ${name.replaceAll('.exe', '')}']);
      }
      final path = (result.stdout as String).trim().split('\n').firstOrNull?.trim();
      if (result.exitCode == 0 && path != null && path.isNotEmpty && await File(path).exists()) {
        return path;
      }
    } on ProcessException {
      // No shell available; managed download takes over.
    }
    return null;
  }

  Future<void> _download(String url, File target, void Function(double?) onProgress) async {
    final client = HttpClient();
    try {
      var uri = Uri.parse(url);
      HttpClientResponse response;
      // Follow redirects manually: GitHub's CDN redirect drops on autoRedirect
      // for some hosts that reject re-sent auth headers.
      while (true) {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        response = await request.close();
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw YtDlpException('Bad redirect from $uri');
          uri = uri.resolve(location);
          await response.drain<void>();
          continue;
        }
        break;
      }
      if (response.statusCode != 200) {
        throw YtDlpException('Download failed (${response.statusCode}) for $url');
      }

      final total = response.contentLength;
      var received = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          onProgress(total > 0 ? received / total : null);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  Future<String> _runVersion(String binary) async {
    final result = await Process.run(binary, ['--version']);
    if (result.exitCode != 0) {
      throw YtDlpException('yt-dlp at $binary failed to run: ${(result.stderr as String).trim()}');
    }
    return (result.stdout as String).trim();
  }

  Future<void> _markExecutable(String path) async {
    if (Platform.isWindows) return;
    await Process.run('chmod', ['+x', path]);
  }
}
