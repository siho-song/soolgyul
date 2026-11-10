/// The one line a list shows for a saved card: its brief (the 핵심 요약 line
/// without its dressing), or on a card made before the brief that line with
/// its `**` bold marks dropped; `null` when the card has neither.
String? tasteCardOneLine({String? brief, String? summary}) {
  final line = brief?.trim().isNotEmpty == true
      ? brief!.trim()
      : summary?.replaceAll('**', '').trim();
  return line == null || line.isEmpty ? null : line;
}
