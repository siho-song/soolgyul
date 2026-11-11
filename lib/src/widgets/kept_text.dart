import 'package:flutter/widgets.dart';

import '../core/format/korean_wrap.dart';

/// A [Text] that wraps between words only, so a line never ends in the
/// middle of a Korean word. It stays a [Text] holding the sentence as
/// written: what is read aloud and what a search finds is unchanged, and
/// only the drawing keeps each word whole. With [sentencePerLine] every
/// sentence after the first starts its own line.
class KeptText extends Text {
  const KeptText(
    super.data, {
    super.key,
    super.style,
    super.textAlign,
    this.sentencePerLine = false,
  });

  final bool sentencePerLine;

  @override
  Widget build(BuildContext context) {
    final written = data ?? '';
    return Text(
      sentencePerLine ? sentencePerLineOf(written) : keepWords(written),
      semanticsLabel: written,
      style: style,
      textAlign: textAlign,
    );
  }
}
