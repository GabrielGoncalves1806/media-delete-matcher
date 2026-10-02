const _months = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

/// 1536 MB -> "1,5 GB", 151000000 -> "144 MB".
String formatBytes(int bytes) {
  const mb = 1024 * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1).replaceAll('.', ',')} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).round()} KB';
}

/// "12 mai 2024"
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "4:02" ou "1:02:33"
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// 11402 -> "11.402"
String formatCount(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

String plural(int n, String singular, String pluralForm) =>
    '${formatCount(n)} ${n == 1 ? singular : pluralForm}';
