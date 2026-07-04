// ignore_for_file: avoid_print
// Engine smoke test: dart tool/smoke.dart [url]
// Exercises binary discovery, metadata fetch, and a real download into /tmp.
import 'dart:io';

import 'package:downpour/src/core/models.dart';
import 'package:downpour/src/core/ytdlp_service.dart';

Future<void> main(List<String> args) async {
  final url = args.firstOrNull ?? 'https://www.youtube.com/watch?v=jNQXAC9IVRw';
  final service = YtDlpService();

  final bin = await service.resolveBinary();
  print('binary: $bin');
  print('version: ${await service.version()}');

  final info = await service.fetchInfo(url);
  print('title: ${info.title}');
  print('uploader: ${info.uploader}');
  print('duration: ${info.durationSeconds}s');
  print('thumbnail: ${info.thumbnail?.substring(0, 60)}...');

  final dir = Directory.systemTemp.createTempSync('downpour-smoke').path;
  final handle = await service.download(url: url, preset: QualityPreset.hd720, directory: dir);

  await for (final event in handle.events) {
    switch (event) {
      case ProgressEvent(:final fraction, :final speed):
        stdout.write('\rprogress: ${((fraction ?? 0) * 100).toStringAsFixed(0)}% '
            'speed: ${speed?.toStringAsFixed(0) ?? '-'} B/s   ');
      case ProcessingEvent():
        print('\nprocessing…');
      case DoneEvent(:final filePath):
        print('\ndone: $filePath');
        final file = filePath == null ? null : File(filePath);
        print('exists: ${file != null && file.existsSync()}, '
            'size: ${file?.lengthSync() ?? 0} bytes');
      case FailedEvent(:final message):
        print('\nFAILED: $message');
        exitCode = 1;
    }
  }
}
