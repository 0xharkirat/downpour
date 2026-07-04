// ignore_for_file: avoid_print
// Engine smoke test: dart tool/smoke.dart [url]
//
// Simulates a first launch on a machine with nothing installed: system
// binaries are ignored, so yt-dlp (and ffmpeg) are downloaded into a temp
// dir, then a real video is fetched and downloaded through them.
import 'dart:io';

import 'package:downpour/src/core/engine_manager.dart';
import 'package:downpour/src/core/models.dart';
import 'package:downpour/src/core/ytdlp_service.dart';

Future<void> main(List<String> args) async {
  final url = args.firstOrNull ?? 'https://www.youtube.com/watch?v=jNQXAC9IVRw';
  final dataDir = Directory.systemTemp.createTempSync('downpour-engine');
  print('engine dir: ${dataDir.path}');

  final manager = EngineManager(dataDirectory: dataDir, useSystemBinaries: false);
  final status = await manager.ensure(onProgress: (p) {
    stdout.write('\r${p.label} ${p.fraction == null ? '' : '${(p.fraction! * 100).toStringAsFixed(0)}%'}   ');
  });
  print('\nyt-dlp: ${status.ytdlpPath} (${status.ytdlpSource.name}, v${status.ytdlpVersion})');
  print('ffmpeg: ${status.ffmpegPath ?? 'UNAVAILABLE'}');

  final service = YtDlpService();
  final info = await service.fetchInfo(url, binary: status.ytdlpPath);
  print('title: ${info.title} (${info.uploader}, ${info.durationSeconds}s)');

  final outDir = Directory.systemTemp.createTempSync('downpour-smoke').path;
  final handle = await service.download(
    url: url,
    preset: QualityPreset.hd720,
    directory: outDir,
    binary: status.ytdlpPath,
    ffmpegPath: status.ffmpegPath,
  );

  await for (final event in handle.events) {
    switch (event) {
      case ProgressEvent(:final fraction):
        stdout.write('\rprogress: ${((fraction ?? 0) * 100).toStringAsFixed(0)}%   ');
      case ProcessingEvent():
        print('\nprocessing…');
      case DoneEvent(:final filePath):
        final file = filePath == null ? null : File(filePath);
        print('\ndone: $filePath '
            '(exists: ${file?.existsSync()}, ${file?.lengthSync() ?? 0} bytes)');
      case FailedEvent(:final message):
        print('\nFAILED: $message');
        exitCode = 1;
    }
  }
}
