import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

class YtDlpException implements Exception {
  YtDlpException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Events emitted while a download runs.
sealed class DownloadEvent {
  const DownloadEvent();
}

class ProgressEvent extends DownloadEvent {
  const ProgressEvent({this.fraction, this.downloadedBytes, this.totalBytes, this.speed, this.etaSeconds});

  final double? fraction;
  final int? downloadedBytes;
  final int? totalBytes;
  final double? speed;
  final int? etaSeconds;
}

class ProcessingEvent extends DownloadEvent {
  const ProcessingEvent();
}

class DoneEvent extends DownloadEvent {
  const DoneEvent(this.filePath);

  final String? filePath;
}

class FailedEvent extends DownloadEvent {
  const FailedEvent(this.message);

  final String message;
}

/// A running download that can be canceled.
class DownloadHandle {
  DownloadHandle._(this.events, this._process);

  final Stream<DownloadEvent> events;
  final Process _process;

  void cancel() {
    _process.kill(ProcessSignal.sigterm);
  }
}

/// Thin wrapper around the yt-dlp CLI.
///
/// Desktop only: mobile platforms cannot spawn external binaries, so an
/// alternative engine must back them (tracked for a later phase).
class YtDlpService {
  String? _cached;

  static const _progressPrefix = 'DP|';

  static List<String> get _candidates {
    final home = Platform.environment['HOME'] ?? '';
    if (Platform.isWindows) {
      final appData = Platform.environment['LOCALAPPDATA'] ?? '';
      return [
        '$appData\\Microsoft\\WinGet\\Links\\yt-dlp.exe',
        '$appData\\Programs\\yt-dlp\\yt-dlp.exe',
        'C:\\ProgramData\\chocolatey\\bin\\yt-dlp.exe',
      ];
    }
    return [
      '/opt/homebrew/bin/yt-dlp',
      '/usr/local/bin/yt-dlp',
      '/usr/bin/yt-dlp',
      '$home/.pyenv/shims/yt-dlp',
      '$home/.local/bin/yt-dlp',
    ];
  }

  /// Resolves the yt-dlp binary path, preferring [override] from settings.
  Future<String> resolveBinary({String? override}) async {
    if (override != null && override.trim().isNotEmpty) {
      if (await File(override.trim()).exists()) return override.trim();
      throw YtDlpException('yt-dlp not found at $override');
    }
    if (_cached != null) return _cached!;

    for (final candidate in _candidates) {
      if (candidate.isNotEmpty && await File(candidate).exists()) {
        return _cached = candidate;
      }
    }

    // GUI apps on macOS/Linux get a minimal PATH; ask a login shell.
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('where', ['yt-dlp']);
      } else {
        final shell = Platform.environment['SHELL'] ?? '/bin/sh';
        result = await Process.run(shell, ['-lc', 'command -v yt-dlp']);
      }
      final path = (result.stdout as String).trim().split('\n').firstOrNull?.trim();
      if (result.exitCode == 0 && path != null && path.isNotEmpty) {
        return _cached = path;
      }
    } on ProcessException {
      // Fall through to the error below.
    }

    throw YtDlpException(
      'yt-dlp was not found. Install it (brew install yt-dlp / winget install yt-dlp) '
      'or set its path in Settings.',
    );
  }

  Future<String> version({String? override}) async {
    final bin = await resolveBinary(override: override);
    final result = await Process.run(bin, ['--version']);
    if (result.exitCode != 0) throw YtDlpException(_tail(result.stderr as String));
    return (result.stdout as String).trim();
  }

  Future<VideoInfo> fetchInfo(String url, {String? override}) async {
    final bin = await resolveBinary(override: override);
    final result = await Process.run(bin, ['-J', '--no-playlist', '--no-warnings', url]);
    if (result.exitCode != 0) {
      throw YtDlpException(_tail(result.stderr as String));
    }
    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    return VideoInfo.fromJson(json);
  }

  /// Starts a download and streams progress events.
  Future<DownloadHandle> download({
    required String url,
    required QualityPreset preset,
    required String directory,
    String? override,
  }) async {
    final bin = await resolveBinary(override: override);
    final args = [
      '--newline',
      '--no-playlist',
      '--no-warnings',
      '--progress-template',
      'download:$_progressPrefix%(progress.downloaded_bytes)s|%(progress.total_bytes)s|'
          '%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s',
      '--no-simulate',
      '--print',
      'after_move:filepath',
      '-o',
      '$directory${Platform.pathSeparator}%(title)s.%(ext)s',
      ...preset.args,
      url,
    ];

    final process = await Process.start(bin, args);
    final controller = StreamController<DownloadEvent>();
    final stderrTail = <String>[];
    String? finalPath;
    var sawFullProgress = false;

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (line.startsWith(_progressPrefix)) {
        final event = _parseProgress(line);
        if (event != null) {
          if ((event.fraction ?? 0) >= 0.999) sawFullProgress = true;
          controller.add(event);
        }
      } else if (line.startsWith('/') || RegExp(r'^[A-Za-z]:\\').hasMatch(line)) {
        finalPath = line.trim();
        if (sawFullProgress) controller.add(const ProcessingEvent());
      }
    });

    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      stderrTail.add(line);
      if (stderrTail.length > 12) stderrTail.removeAt(0);
    });

    unawaited(process.exitCode.then((code) async {
      if (code == 0) {
        controller.add(DoneEvent(finalPath));
      } else if (code == -15 || code == 143 || code == 1 && finalPath == null && stderrTail.isEmpty) {
        // SIGTERM from cancel; the notifier already marked the task canceled.
        controller.add(const FailedEvent('Canceled'));
      } else {
        controller.add(FailedEvent(_tail(stderrTail.join('\n'))));
      }
      await controller.close();
    }));

    return DownloadHandle._(controller.stream, process);
  }

  ProgressEvent? _parseProgress(String line) {
    final parts = line.substring(_progressPrefix.length).split('|');
    if (parts.length < 5) return null;
    int? asInt(String s) => double.tryParse(s)?.round();
    final downloaded = asInt(parts[0]);
    final total = asInt(parts[1]) ?? asInt(parts[2]);
    final speed = double.tryParse(parts[3]);
    final eta = asInt(parts[4]);
    final fraction = (downloaded != null && total != null && total > 0)
        ? (downloaded / total).clamp(0.0, 1.0)
        : null;
    return ProgressEvent(
      fraction: fraction,
      downloadedBytes: downloaded,
      totalBytes: total,
      speed: speed,
      etaSeconds: eta,
    );
  }

  String _tail(String stderr) {
    final lines = stderr.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return 'yt-dlp failed with no error output';
    final errorLine = lines.lastWhere((l) => l.contains('ERROR'), orElse: () => lines.last);
    return errorLine.replaceFirst(RegExp(r'^ERROR:\s*'), '').trim();
  }
}
