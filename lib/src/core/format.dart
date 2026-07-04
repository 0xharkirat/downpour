/// Human-readable formatting helpers.
library;

String formatBytes(num? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

String formatSpeed(double? bytesPerSecond) =>
    bytesPerSecond == null ? '—' : '${formatBytes(bytesPerSecond)}/s';

String formatEta(int? seconds) {
  if (seconds == null || seconds < 0) return '—';
  final d = Duration(seconds: seconds);
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inSeconds}s';
}

String formatDuration(int? seconds) {
  if (seconds == null) return '';
  final d = Duration(seconds: seconds);
  final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
  final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$mm:$ss' : '${d.inMinutes}:$ss';
}
