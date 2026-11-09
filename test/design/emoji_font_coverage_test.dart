import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The bundled emoji font is cut down to the emoji the app writes, so an
/// emoji added to the code without being added to the font would come back
/// as a box on the web. Every emoji in `lib/` must be in the font's cmap.
void main() {
  test('every emoji written in lib is in the bundled emoji font', () {
    final font = File(
      'assets/fonts/noto_color_emoji/NotoColorEmoji-Subset.ttf',
    );
    final covered = _cmapCodePoints(font.readAsBytesSync());

    final missing = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final rune in _code(file.readAsStringSync()).runes) {
        if (_isEmoji(rune) && !covered.contains(rune)) {
          missing.add(
            'U+${rune.toRadixString(16).toUpperCase()} '
            '${String.fromCharCode(rune)} in ${file.path}',
          );
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'Run tools/fonts/subset_emoji.sh to add them to the font.',
    );
  });
}

/// The file without its comment lines: an emoji in a comment is never drawn.
String _code(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// Emoji proper, plus the variation selector that asks for the emoji
/// look (U+FE0F): the web engine treats it as a character to cover too.
bool _isEmoji(int rune) =>
    rune == 0xFE0F ||
    (rune >= 0x1F000 && rune <= 0x1FAFF) ||
    (rune >= 0x2300 && rune <= 0x23FF) ||
    (rune >= 0x2600 && rune <= 0x27BF) ||
    (rune >= 0x2B00 && rune <= 0x2BFF);

/// The code points a TrueType font maps, read from its cmap subtables of
/// format 4 (BMP) and 12 (full range).
Set<int> _cmapCodePoints(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final tableCount = data.getUint16(4);
  var cmapOffset = -1;
  for (var i = 0; i < tableCount; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag == 'cmap') cmapOffset = data.getUint32(record + 8);
  }
  if (cmapOffset < 0) fail('no cmap table');

  final points = <int>{};
  final subtableCount = data.getUint16(cmapOffset + 2);
  for (var i = 0; i < subtableCount; i++) {
    final offset = cmapOffset + data.getUint32(cmapOffset + 4 + i * 8 + 4);
    switch (data.getUint16(offset)) {
      case 4:
        final segments = data.getUint16(offset + 6) ~/ 2;
        for (var s = 0; s < segments; s++) {
          final end = data.getUint16(offset + 14 + s * 2);
          final start = data.getUint16(offset + 16 + segments * 2 + s * 2);
          if (start == 0xFFFF) continue;
          for (var c = start; c <= end; c++) {
            points.add(c);
          }
        }
      case 12:
        final groups = data.getUint32(offset + 12);
        for (var g = 0; g < groups; g++) {
          final group = offset + 16 + g * 12;
          final start = data.getUint32(group);
          final end = data.getUint32(group + 4);
          for (var c = start; c <= end; c++) {
            points.add(c);
          }
        }
    }
  }
  return points;
}
