/// Which of a label's lines are searched, and as what: the first of the
/// label search's three steps (find candidates, weigh them, decide).
library;

import 'label_words.dart';

/// Lines that only state strength or volume ("ALC. 40% VOL", "750ml",
/// "15% BY VOLUME", "알코올 17도"); they never name the drink.
final RegExp _strengthOrVolumeLine = RegExp(
  r'^(alc\.?|alcohol|abv|vol\.?|volume|by|cont\.?|contents?|ml|cl|l|e|도|용량|'
  r'알코올|알콜|[\d%.,:/\s\-])+$',
  caseSensitive: false,
);

/// Japanese labels put the kind right after the name with no space
/// ("風の森純米大吟醸"), so these are cut out of a word wherever they occur,
/// longest first.
const List<String> _japaneseKindWords = <String>[
  '純米大吟醸',
  '純米吟醸',
  '大吟醸',
  '本醸造',
  '特別純米',
  '純米',
  '吟醸',
  '清酒',
  '日本酒',
  '本格焼酎',
  '焼酎',
  '無濾過',
  '生原酒',
  '原酒',
  '生酒',
  '生詰',
  '火入',
  '精米歩合',
  '株式会社',
  '合資会社',
  '製造者',
  '内容量',
  '特別',
];

String _withoutJapaneseKind(String word) {
  var result = word;
  for (final kind in _japaneseKindWords) {
    result = result.replaceAll(kind, '');
  }
  return result;
}

final RegExp _letters = RegExp(r'\p{L}', unicode: true);
final RegExp _bracket = RegExp(r'[()（）\[\]]');

/// Lines that name the company behind the bottle, not the drink ("JOHN
/// WALKER & SONS LIMITED", "BY APPOINTMENT TO", "수입원 (주)…").
final RegExp _companyLine = RegExp(
  r'\b(?:limited|ltd|inc|appointment)\b|&\s*sons\b|'
  r'\b(?:bottled|produced|imported|distilled)\s+(?:and\s+\w+\s+)?by\b|'
  r'\bproduct\s+of\b|주식회사|\(주\)|㈜|유한회사',
  caseSensitive: false,
);
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _edgePunctuation = RegExp(
  r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
  unicode: true,
);

final RegExp _numberName = RegExp(r'^\d{4}$');
final RegExp _vintage = RegExp(r'^(?:19|20)\d\d$');

/// The label lines worth searching the catalog with, in label order, each
/// stripped of its kind words; a bracketed part is a line of its own. Drops strength and volume statements, bare
/// numbers, symbols, back-label paragraphs, company lines, lines of nothing
/// but kind words, and repeats.
List<String> labelSearchQueries(
  List<String> lines, {
  int limit = 6,
  int maxLength = 40,
}) {
  final seen = <String>{};
  final queries = <String>[];
  final parts = lines
      .where((line) => !_companyLine.hasMatch(line))
      .expand((line) => line.split(_bracket));
  for (final raw in parts) {
    final line = raw.replaceAll(_whitespace, ' ').trim();
    if (line.length > maxLength) continue;
    // A name that is a number ("1865", "1800"), which is no vintage.
    if (_numberName.hasMatch(line) && !_vintage.hasMatch(line)) {
      if (seen.add(line)) queries.add(line);
      if (queries.length == limit) break;
      continue;
    }
    if (_strengthOrVolumeLine.hasMatch(line)) continue;
    final words = line
        .split(' ')
        .map((word) => word.replaceAll(_edgePunctuation, ''))
        .where((word) => !labelKindWords.contains(word.toLowerCase()))
        .map(_withoutJapaneseKind)
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final query = words.join(' ');
    if (_letters.allMatches(query).length < 2) continue;
    if (!seen.add(query.toLowerCase())) continue;
    queries.add(query);
    if (queries.length == limit) break;
  }
  return queries;
}

/// 제품명 or 품명 on a Korean back label, up to where its value starts.
final RegExp _productNameKey = RegExp(
  r'(?:제\s*품\s*명|(?<![가-힣])품\s*명)[\s:：;》>\])\-]*',
);

/// Where the value ends: the next numbered field, a divider, or the name
/// of the field that follows on the same line.
final RegExp _productNameEnd = RegExp(
  r'\s[2-9]\s*[.,)]|[/|•·(（\[]|(?:\s\d)?\s*(?:식품\s*의?\s*유형|제품\s*유형|유형|'
  r'원재료|에탄올|알코올|알콜|내용량|용량|원산지|업소명|수입|제조|도수|소비기한|'
  r'유통기한|보관|반품)',
);

/// The drink's name as a Korean back label states it ("제품명: 그란츠
/// 트리플우드"), which is the one line of that label that names the drink.
/// `null` when no line carries the field with its value.
String? labelProductName(List<String> lines) {
  for (final raw in lines) {
    final line = raw.replaceAll(_whitespace, ' ');
    final key = _productNameKey.firstMatch(line);
    if (key == null) continue;
    var value = line.substring(key.end);
    final end = _productNameEnd.firstMatch(value);
    if (end != null) value = value.substring(0, end.start);
    value = value
        .split(' ')
        .map((word) => word.replaceAll(_edgePunctuation, ''))
        .where((word) => word.isNotEmpty)
        .join(' ');
    if (_letters.allMatches(value).length >= 2) return value;
  }
  return null;
}

final RegExp _hangul = RegExp(r'[가-힣]');
final RegExp _latinLetter = RegExp(r'[A-Za-z]');

/// The searches to try for a back label's product name: as printed, its
/// Korean words alone (the label often repeats the name in Latin letters),
/// and each without its last word, which is where a label adds what the
/// catalog leaves out ("디오씨지", "레이블").
List<String> productNameQueries(String name) {
  final words = name.split(' ');
  final korean = words
      .where((word) => _hangul.hasMatch(word) && !_latinLetter.hasMatch(word))
      .toList(growable: false);
  final seen = <String>{};
  return <List<String>>[
        words,
        korean,
        if (words.length > 1) words.sublist(0, words.length - 1),
        if (korean.length > 1) korean.sublist(0, korean.length - 1),
      ]
      .map((variant) => variant.join(' '))
      .where((query) => _letters.allMatches(query).length >= 2)
      .where(seen.add)
      .toList(growable: false);
}

/// Each naming line joined with the next and with the one after it: a
/// label spreads a name over lines ("MONTES ALPHA", "CABERNET SAUVIGNON"),
/// and only the search for both finds that one drink among its maker's.
List<String> labelPairQueries(List<String> queries) => <String>[
  for (var i = 0; i + 1 < queries.length; i++)
    '${queries[i]} ${queries[i + 1]}',
  for (var i = 0; i + 2 < queries.length; i++)
    '${queries[i]} ${queries[i + 2]}',
];

/// Words a Korean back label carries and a front label does not.
final RegExp _backLabelWord = RegExp(
  r'원재료|식품\s*의?\s*유형|수입\s*(?:원|업)|반품|소비자\s*분쟁|품목\s*보고|내용량',
);

bool isBackLabel(List<String> lines) {
  final text = lines.join(' ');
  return _backLabelWord.allMatches(text).map((m) => m[0]).toSet().length >= 2;
}

/// Whether [line] names the company behind the bottle, not the drink.
bool isCompanyLine(String line) => _companyLine.hasMatch(line);

/// A price or a bullet in a list line ("- ", "B 59.0 / G 12.0", "19,900원"),
/// which is not part of the drink's name.
final RegExp _listBullet = RegExp(r'^[\s\-–—•·.*]+');
final RegExp _listPrice = RegExp(
  r'[₩￦]\s*\d[\d,.]*|\d[\d,.]*\s*(?:만\s*원|천\s*원|원|won|krw)|'
  r'(?<![\p{L}\p{N}])[BG]\s*\d+(?:[.,]\d+)?(?![\p{L}\p{N}])|'
  r'\d{1,3}(?:,\d{3})+|\d+\.\d+',
  caseSensitive: false,
  unicode: true,
);

String listEntryName(String line) => line
    .replaceAll(_listPrice, ' ')
    .replaceAll(_listBullet, '')
    .replaceAll('/', ' ')
    .replaceAll(_whitespace, ' ')
    .trim();
