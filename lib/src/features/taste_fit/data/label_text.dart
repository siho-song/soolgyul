/// Text as a label search compares it: a drink's name and the lines read
/// off a label, folded to one spelling and cut into words.
library;

final RegExp _apostrophe = RegExp("['’‘`´]");
final RegExp _wordRun = RegExp(r'[a-z]+|\d+|[가-힣]+|[぀-ヿ㐀-鿿]+');
final RegExp _latinRun = RegExp(r'^[a-z]+$');
final RegExp _digitRun = RegExp(r'^\d+$');
final RegExp _hangulRun = RegExp(r'^[가-힣]+$');
final RegExp _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);
final RegExp _vintageWord = RegExp(r'^(?:19|20)\d\d$');
final RegExp _vintageInName = RegExp(r'\s*(?:19|20)\d\d(?!\d)');

const String _accented = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
const String _plain = 'aaaaaaceeeeiiiinooooouuuuyy';

/// Spellings an import label uses for a word the catalog writes one way.
const Map<String, String> _catalogSpelling = <String, String>{
  '레이블': '라벨',
  '카버네': '까베르네',
  '카베르네': '까베르네',
  '까베네': '까베르네',
  '까쇼': '까베르네 소비뇽',
  '쇼비뇽': '소비뇽',
  '쏘비뇽': '소비뇽',
  '샤도네이': '샤르도네',
  '샤도네': '샤르도네',
  '시라즈': '쉬라즈',
  '삐노': '피노',
  '누아르': '누아',
  '메를롯': '메를로',
  '멜롯': '메를로',
};

/// Lower case, in the catalog's spelling, without accents and apostrophes,
/// so "Grant's" and "Rosé" compare as "grants" and "rose".
String foldLabelText(String text) {
  var lower = text.toLowerCase().replaceAll(_apostrophe, '');
  for (final MapEntry(key: label, value: catalog) in _catalogSpelling.entries) {
    lower = lower.replaceAll(label, catalog);
  }
  final folded = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final at = _accented.indexOf(char);
    folded.write(at < 0 ? char : _plain[at]);
  }
  return folded.toString();
}

/// The words of [text] once folded, in order: runs of Latin letters, of
/// digits, of Hangul and of kana or kanji.
Iterable<String> labelWords(String text) =>
    _wordRun.allMatches(foldLabelText(text)).map((match) => match[0]!);

bool isLatinWord(String word) => _latinRun.hasMatch(word);
bool isNumberWord(String word) => _digitRun.hasMatch(word);

/// A year a bottle can carry ("2019"), which is its bottling and not its
/// name.
bool isVintageWord(String word) => _vintageWord.hasMatch(word);

/// A drink's name without its year: one drink's years are one drink.
String withoutVintage(String name) => name.replaceAll(_vintageInName, '');

/// A word a label read cannot be checked for: one or two Latin letters
/// ("M", "XR") or a single Korean syllable are no different from a scrap.
bool isTooShortToRead(String word) => isLatinWord(word)
    ? word.length < 3
    : !isNumberWord(word) && word.length < 2;

/// What a label's lines hold, ready to be asked whether they show a word.
class LabelText {
  LabelText(Iterable<String> lines) {
    for (final line in lines) {
      final folded = foldLabelText(line);
      _squeezed.add(folded.replaceAll(_notLetterOrDigit, ''));
      String? before;
      for (final match in _wordRun.allMatches(folded)) {
        final word = match[0]!;
        words.add(word);
        if (isLatinWord(word)) {
          _latin.add(word);
          // "T IPLE" is "TRIPLE" read with a gap.
          if (before != null) _latin.add('$before$word');
          before = word;
        } else {
          before = null;
        }
      }
    }
  }

  /// Every word read, as read.
  final Set<String> words = <String>{};
  final Set<String> _latin = <String>{};
  final List<String> _squeezed = <String>[];

  /// How surely the lines show [word], a word of a folded name: 1 as
  /// written, 0.8 a letter or two off (which only a longer word can
  /// afford), 0 not at all. A Korean word is looked for inside the line,
  /// since a label runs Korean words together.
  double shows(String word) {
    if (isNumberWord(word)) return words.contains(word) ? 1 : 0;
    if (isLatinWord(word)) return _showsLatin(word);
    if (_squeezed.any((line) => line.contains(word))) return 1;
    return _showsHangulNearly(word);
  }

  double _showsLatin(String word) {
    if (_latin.contains(word)) return 1;
    final allowed = word.length >= 9
        ? 2
        : word.length >= 5
        ? 1
        : 0;
    if (allowed == 0) return 0;
    for (final read in _latin) {
      if ((read.length - word.length).abs() > allowed) continue;
      if (_editDistance(read, word, allowed) <= allowed) return 0.8;
    }
    return 0;
  }

  /// A Korean word read one stroke off ("가쿠반" for 가쿠빈), which only a
  /// word of three syllables or more can afford.
  double _showsHangulNearly(String word) {
    if (word.length < 3 || !_hangulRun.hasMatch(word)) return 0;
    final strokes = _strokes(word);
    for (final line in _squeezed) {
      for (var at = 0; at + word.length <= line.length; at++) {
        final read = line.substring(at, at + word.length);
        if (!_hangulRun.hasMatch(read)) continue;
        if (_editDistance(_strokes(read), strokes, 1) <= 1) return 0.8;
      }
    }
    return 0;
  }
}

/// A Korean word as its consonants and vowels, three to a syllable, so two
/// words one stroke apart differ by one letter.
String _strokes(String word) {
  final strokes = StringBuffer();
  for (final rune in word.runes) {
    final code = rune - 0xAC00;
    strokes
      ..writeCharCode(0x1100 + code ~/ 588)
      ..writeCharCode(0x1161 + code % 588 ~/ 28)
      ..writeCharCode(0x11A7 + code % 28);
  }
  return strokes.toString();
}

/// Edits between [a] and [b], or more than [cap] once it is past it.
int _editDistance(String a, String b, int cap) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, i);
    var rowBest = i;
    for (var j = 1; j <= b.length; j++) {
      final swap = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final drop = previous[j] + 1;
      final add = current[j - 1] + 1;
      final cell = swap < drop
          ? (swap < add ? swap : add)
          : (drop < add ? drop : add);
      current[j] = cell;
      if (cell < rowBest) rowBest = cell;
    }
    if (rowBest > cap) return cap + 1;
    previous = current;
  }
  return previous[b.length];
}
