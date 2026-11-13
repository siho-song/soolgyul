import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

/// U+2060 WORD JOINER: no line may break on either side of it.
const wordJoiner = '⁠';

final _space = RegExp(r'\s');

/// Text that wraps between words only. Korean breaks between any two
/// letters by default, which leaves one letter alone on the last line; a
/// word joiner between the letters of a word keeps the word whole. Spaces
/// and line ends stay where lines may break. A word wider than a whole line
/// still breaks inside, as the text layout does with any word too long for
/// its line, so it never runs past the edge. For display only: what the
/// reader typed, what is stored or sent, and what is read aloud stay as
/// written.
String keepWords(String text) => text
    .split('\n')
    .map(
      (line) => line
          .split(' ')
          .map((word) => word.characters.join(wordJoiner))
          .join(' '),
    )
    .join('\n');

/// [keepWords], with every sentence after the first on its own line: a
/// notice says what happened, then under it what to do.
String sentencePerLineOf(String text) =>
    keepWords(text.replaceAll(RegExp(r'(?<=[.!?])\s+'), '\n'));

/// [keepWords] over every piece of [span]. A word that runs across two
/// pieces, such as a bold **산미** and the 가 after it, or a word drawn as
/// a widget, stays whole too. Each changed piece reads aloud as written.
InlineSpan keepSpanWords(InlineSpan span) {
  // The pieces in reading order: a text, or null for a widget, which
  // counts as part of a word.
  final pieces = <String?>[];
  void collect(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text case final text?) pieces.add(text);
      span.children?.forEach(collect);
    } else {
      pieces.add(null);
    }
  }

  collect(span);
  final joined = <String?>[];
  for (var i = 0; i < pieces.length; i++) {
    final text = pieces[i];
    if (text == null) {
      joined.add(null);
      continue;
    }
    var kept = keepWords(text);
    if (text.isNotEmpty) {
      if (!_space.hasMatch(text[0]) && _endsInWord(pieces, i)) {
        kept = '$wordJoiner$kept';
      }
      if (!_space.hasMatch(text[text.length - 1]) &&
          i + 1 < pieces.length &&
          pieces[i + 1] == null) {
        kept = '$kept$wordJoiner';
      }
    }
    joined.add(kept);
  }

  var next = 0;
  InlineSpan rebuild(InlineSpan span) {
    if (span is! TextSpan) {
      next++;
      return span;
    }
    final text = span.text;
    final kept = text == null ? null : joined[next++];
    return TextSpan(
      text: kept,
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel:
          span.semanticsLabel ?? (kept != text && text != '' ? text : null),
      semanticsIdentifier: span.semanticsIdentifier,
      locale: span.locale,
      spellOut: span.spellOut,
      children: span.children?.map(rebuild).toList(),
    );
  }

  return rebuild(span);
}

/// Whether the last non-empty piece before [index] ends inside a word.
bool _endsInWord(List<String?> pieces, int index) {
  for (var i = index - 1; i >= 0; i--) {
    final piece = pieces[i];
    if (piece == null) return true;
    if (piece.isEmpty) continue;
    return !_space.hasMatch(piece[piece.length - 1]);
  }
  return false;
}
