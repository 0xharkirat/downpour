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

/// Thin wrapper around the yt-dlp CLI. Binary paths are resolved by
/// [EngineManager]; this class only runs them.
class YtDlpService {
  static const _progressPrefix = 'DP|';

  Future<VideoInfo> fetchInfo(String url, {required String binary}) async {
    final result = await Process.run(binary, ['-J', '--no-playlist', '--no-warnings', url]);
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
    required String binary,
    String? ffmpegPath,
  }) async {
    final args = [
      '--newline',
      // --print implies --quiet, which silences progress; force it back on.
      '--progress',
      '--no-playlist',
      '--no-warnings',
      '--progress-template',
      'download:$_progressPrefix%(progress.downloaded_bytes)s|%(progress.total_bytes)s|'
          '%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s',
      '--no-simulate',
      '--print',
      'after_move:filepath',
      if (ffmpegPath != null) ...['--ffmpeg-location', ffmpegPath],
      // Preset in the filename so the same video can exist at several
      // qualities; otherwise yt-dlp sees the file and skips the download.
      '-o',
      '$directory${Platform.pathSeparator}%(title)s [${preset.label}].%(ext)s',
      ...preset.args(ffmpegAvailable: ffmpegPath != null),
      url,
    ];

    final process = await Process.start(binary, args);
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
