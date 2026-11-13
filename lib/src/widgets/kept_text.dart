import 'package:flutter/widgets.dart';

import '../core/format/korean_wrap.dart';

/// A [Text] that wraps between words only, so a line never ends in the
/// middle of a Korean word. It stays a [Text] holding the sentence as
/// written: what is read aloud and what a search finds is unchanged, and
/// only the drawing keeps each word whole. With [sentencePerLine] every
/// sentence after the first starts its own line. [KeptText.rich] does the
/// same for styled pieces, a bold word inside a sentence included.
///
/// For prose on display only: a label, a number or what the reader types
/// is drawn with a plain [Text].
class KeptText extends Text {
  const KeptText(
    super.data, {
    super.key,
    super.style,
    super.textAlign,
    super.maxLines,
    super.overflow,
    super.textScaler,
    super.semanticsLabel,
    this.sentencePerLine = false,
  });

  const KeptText.rich(
    super.textSpan, {
    super.key,
    super.style,
    super.textAlign,
    super.maxLines,
    super.overflow,
    super.textScaler,
  }) : sentencePerLine = false,
       super.rich();

  final bool sentencePerLine;

  @override
  Widget build(BuildContext context) {
    final written = data;
    final span = textSpan;
    // The joined copy is drawn by [Text]'s own build, so the tree holds this
    // one [Text], with the sentence as written.
    final Text drawn;
    if (written != null) {
      final kept = sentencePerLine
          ? sentencePerLineOf(written)
          : keepWords(written);
      if (kept == written) return super.build(context);
      drawn = Text(
        kept,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        textScaler: textScaler,
        semanticsLabel: semanticsLabel ?? written,
      );
    } else {
      drawn = Text.rich(
        keepSpanWords(span!),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        textScaler: textScaler,
      );
    }
    return drawn.build(context);
  }
}
