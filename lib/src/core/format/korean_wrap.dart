/// Text that wraps between words only. Korean breaks between any two
/// letters by default, which leaves one letter alone on the last line; a
/// word joiner between the letters of a word keeps the word whole.
String keepWords(String text) => text
    .split('\n')
    .map(
      (line) =>
          line.split(' ').map((word) => word.split('').join('⁠')).join(' '),
    )
    .join('\n');

/// [keepWords], with every sentence after the first on its own line: a
/// notice says what happened, then under it what to do.
String sentencePerLineOf(String text) =>
    keepWords(text.replaceAll(RegExp(r'(?<=[.!?])\s+'), '\n'));
