/// `2026.06.18`: the date as the app writes it, without an intl dependency.
String formatDotDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}.${two(date.month)}.${two(date.day)}';
}
