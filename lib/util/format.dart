/// Formats a duration as `m:ss`, or `h:mm:ss` once it reaches an hour.
String formatDuration(Duration duration) {
  final negative = duration.isNegative;
  final d = duration.abs();
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final body = hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds' : '$minutes:$seconds';
  return negative ? '-$body' : body;
}

String formatSeconds(int seconds) => formatDuration(Duration(seconds: seconds));

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}
