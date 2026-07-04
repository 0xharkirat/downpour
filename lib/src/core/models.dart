/// Core domain models for Downpour.
library;

/// Quality presets mapped to yt-dlp format selectors.
enum QualityPreset {
  best('Best', null),
  uhd2160('4K', 2160),
  hd1080('1080p', 1080),
  hd720('720p', 720),
  audio('Audio', null);

  const QualityPreset(this.label, this.maxHeight);

  final String label;
  final int? maxHeight;

  /// yt-dlp arguments for this preset. Without ffmpeg, streams can't be
  /// merged or converted, so selectors degrade to single-file formats.
  List<String> args({required bool ffmpegAvailable}) {
    if (this == QualityPreset.audio) {
      return ffmpegAvailable
          ? const ['-x', '--audio-format', 'mp3', '--audio-quality', '0']
          : const ['-f', 'ba[ext=m4a]/ba/b'];
    }
    final h = maxHeight == null ? '' : '[height<=$maxHeight]';
    return ffmpegAvailable ? ['-f', 'bv*$h+ba/b$h'] : ['-f', 'b$h/b'];
  }
}

/// Metadata about a video, parsed from `yt-dlp -J`.
class VideoInfo {
  const VideoInfo({
    required this.title,
    required this.webpageUrl,
    this.thumbnail,
    this.uploader,
    this.durationSeconds,
    this.extractor,
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) => VideoInfo(
        title: (json['title'] as String?) ?? 'Untitled',
        webpageUrl: (json['webpage_url'] as String?) ?? '',
        thumbnail: json['thumbnail'] as String?,
        uploader: (json['uploader'] ?? json['channel'] ?? json['uploader_id']) as String?,
        durationSeconds: (json['duration'] as num?)?.round(),
        extractor: json['extractor_key'] as String?,
      );

  final String title;
  final String webpageUrl;
  final String? thumbnail;
  final String? uploader;
  final int? durationSeconds;
  final String? extractor;
}

enum DownloadStatus { fetching, downloading, processing, done, error, canceled }

extension DownloadStatusX on DownloadStatus {
  bool get isActive =>
      this == DownloadStatus.fetching ||
      this == DownloadStatus.downloading ||
      this == DownloadStatus.processing;
}

/// A single download in the queue. Immutable; updated via [copyWith].
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.url,
    required this.preset,
    required this.status,
    this.info,
    this.progress,
    this.downloadedBytes,
    this.totalBytes,
    this.speed,
    this.etaSeconds,
    this.filePath,
    this.error,
  });

  final String id;
  final String url;
  final QualityPreset preset;
  final DownloadStatus status;
  final VideoInfo? info;

  /// 0.0 to 1.0, null when unknown.
  final double? progress;
  final int? downloadedBytes;
  final int? totalBytes;

  /// Bytes per second.
  final double? speed;
  final int? etaSeconds;
  final String? filePath;
  final String? error;

  DownloadTask copyWith({
    DownloadStatus? status,
    VideoInfo? info,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    double? speed,
    int? etaSeconds,
    String? filePath,
    String? error,
  }) =>
      DownloadTask(
        id: id,
        url: url,
        preset: preset,
        status: status ?? this.status,
        info: info ?? this.info,
        progress: progress ?? this.progress,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        speed: speed ?? this.speed,
        etaSeconds: etaSeconds ?? this.etaSeconds,
        filePath: filePath ?? this.filePath,
        error: error ?? this.error,
      );

  String get displayTitle => info?.title ?? url;
}
