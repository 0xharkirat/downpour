import 'dart:io';

import 'ytdlp_service.dart';

class TranscriptSegment {
  const TranscriptSegment({required this.start, required this.text});

  final Duration start;
  final String text;

  String get timestamp {
    final mm = (start.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (start.inSeconds % 60).toString().padLeft(2, '0');
    return start.inHours > 0 ? '${start.inHours}:$mm:$ss' : '$mm:$ss';
  }
}

/// Fetches video transcripts.
///
/// Engine 1: platform captions via yt-dlp (manual subs preferred, then
/// auto-generated). Instant and covers most videos. A local whisper.cpp
/// engine for caption-less videos is planned as a fallback.
class TranscriptService {
  /// Returns the transcript as SRT, or null when the video has no captions.
  Future<String?> fetchCaptions({
    required String url,
    required String binary,
    String? ffmpegPath,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('downpour-subs');
    try {
      // Only plain English tracks: wildcards like en.* match auto-translated
      // variants, which multiplies requests and trips YouTube's rate limit.
      final result = await Process.run(binary, [
        '--skip-download',
        '--no-playlist',
        '--no-warnings',
        '--write-subs',
        '--write-auto-subs',
        '--sub-langs',
        'en,en-orig',
        '--convert-subs',
        'srt',
        if (ffmpegPath != null) ...['--ffmpeg-location', ffmpegPath],
        '-o',
        '${tmp.path}${Platform.pathSeparator}sub.%(ext)s',
        url,
      ]);

      // A failed variant can exit non-zero after a usable track was written,
      // so look for files first and only then surface the error.
      final files = tmp.listSync().whereType<File>().toList();
      final subtitle = files.where((f) => f.path.endsWith('.srt')).firstOrNull ??
          files.where((f) => f.path.endsWith('.vtt')).firstOrNull;
      if (subtitle != null) return subtitle.readAsString();
      if (result.exitCode != 0) {
        throw YtDlpException(
          (result.stderr as String).trim().split('\n').lastOrNull ?? 'Caption fetch failed',
        );
      }
      return null;
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  /// Parses SRT into display segments, merging the cue index/timing noise
  /// away and deduplicating the rolling repeats in auto-generated captions.
  List<TranscriptSegment> parseSrt(String srt) {
    final segments = <TranscriptSegment>[];
    final blocks = srt.replaceAll('\r\n', '\n').split(RegExp(r'\n\n+'));
    // Hours are optional: WebVTT allows MM:SS.mmm for short videos.
    final timing = RegExp(r'(?:(\d{1,2}):)?(\d{2}):(\d{2})[,.](\d{3})\s*-->');

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;
      final match = timing.firstMatch(block);
      if (match == null) continue;
      final start = Duration(
        hours: int.parse(match.group(1) ?? '0'),
        minutes: int.parse(match.group(2)!),
        seconds: int.parse(match.group(3)!),
        milliseconds: int.parse(match.group(4)!),
      );
      final text = lines
          .skipWhile((l) => !l.contains('-->'))
          .skip(1)
          .join(' ')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) continue;
      // Auto-captions repeat the previous line in each cue; drop duplicates.
      if (segments.isNotEmpty && segments.last.text == text) continue;
      if (segments.isNotEmpty && text.startsWith(segments.last.text)) {
        segments[segments.length - 1] = TranscriptSegment(
          start: segments.last.start,
          text: text,
        );
        continue;
      }
      segments.add(TranscriptSegment(start: start, text: text));
    }
    return segments;
  }

  /// Plain-text rendering used for the sidecar file and clipboard.
  String toPlainText(List<TranscriptSegment> segments) =>
      segments.map((s) => '[${s.timestamp}] ${s.text}').join('\n');
}
