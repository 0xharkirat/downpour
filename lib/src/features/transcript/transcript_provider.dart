import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database.dart';
import '../../core/engine_provider.dart';
import '../../core/transcript_service.dart';
import '../../core/ytdlp_service.dart';

final transcriptServiceProvider = Provider<TranscriptService>((_) => TranscriptService());

class TranscriptResult {
  const TranscriptResult({required this.record, required this.segments, this.sidecarPath});

  final DownloadRecord record;

  /// Empty means the video has no captions.
  final List<TranscriptSegment> segments;

  /// The .txt written next to the downloaded video, when possible.
  final String? sidecarPath;
}

/// Loads (and caches in the database) the transcript for a finished download.
final transcriptProvider =
    FutureProvider.autoDispose.family<TranscriptResult, int>((ref, recordId) async {
  final db = ref.watch(databaseProvider);
  final service = ref.watch(transcriptServiceProvider);

  final record = await db.recordById(recordId);
  if (record == null) throw YtDlpException('Download no longer exists');

  var srt = record.transcriptSrt;
  var sidecarPath = record.transcriptPath;

  if (srt == null) {
    final engine = await ref.watch(engineProvider.future);
    srt = await service.fetchCaptions(
      url: record.url,
      binary: engine.ytdlpPath,
      ffmpegPath: engine.ffmpegPath,
    );
    if (srt == null) {
      // Cache the miss so we don't hammer the site on every open.
      await db.saveTranscript(recordId, '', null);
      return TranscriptResult(record: record, segments: const []);
    }

    // Write a readable sidecar next to the video: "Title [Best].txt".
    final videoPath = record.filePath;
    if (videoPath != null && await File(videoPath).exists()) {
      final base = videoPath.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
      final sidecar = File('$base.txt');
      await sidecar.writeAsString(service.toPlainText(service.parseSrt(srt)));
      sidecarPath = sidecar.path;
    }
    await db.saveTranscript(recordId, srt, sidecarPath);
  }

  return TranscriptResult(
    record: record,
    segments: srt.isEmpty ? const [] : service.parseSrt(srt),
    sidecarPath: sidecarPath,
  );
});
