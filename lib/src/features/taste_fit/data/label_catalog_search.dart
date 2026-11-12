import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';

/// Lines that only state strength or volume ("ALC. 40% VOL", "750ml",
/// "알코올 17도"); they never name the drink.
final RegExp _strengthOrVolumeLine = RegExp(
  r'^(alc\.?|alcohol|abv|vol\.?|ml|cl|l|e|도|용량|알코올|알콜|[\d%.,:/\s])+$',
  caseSensitive: false,
);

/// Words every label of a kind carries ("single malt", "scotch whisky",
/// "純米大吟醸", "증류식 소주"). A line made of them names a category, not a
/// drink, and would pull in every drink of that kind; inside a naming line
/// they only narrow the every-word match for nothing.
const Set<String> _kindWords = <String>{
  // whisky and spirits
  'single', 'malt', 'malts', 'scotch', 'whisky', 'whiskey', 'bourbon',
  'blended', 'blend', 'grain', 'cask', 'strength', 'aged', 'years', 'year',
  'old', 'reserve', 'premium', 'special', 'distillery', 'distilled',
  'bottled', 'matured', 'finish', 'finished', 'product', 'of', 'the', 'and',
  'scotland', 'highland', 'speyside', 'islay', 'japan', 'korea', 'france',
  'italy', 'spain', 'gin', 'vodka', 'rum', 'tequila', 'brandy', 'cognac',
  'liqueur', 'spirit', 'spirits', 'beer', 'lager', 'ale',
  // wine
  'wine', 'vin', 'vino', 'red', 'white', 'rose', 'rosé', 'rouge', 'blanc',
  'rosso', 'bianco', 'tinto', 'blanco', 'brut', 'sec', 'dry', 'sweet',
  'sparkling', 'champagne', 'de', 'du', 'des', 'la', 'le', 'les', 'di', 'del',
  'della', 'appellation', 'controlee', 'contrôlée', 'doc', 'docg', 'aoc',
  // sake and shochu
  'sake', 'junmai', 'ginjo', 'daiginjo', 'honjozo', 'nigori', 'genshu',
  'namazake', 'tokubetsu', 'shochu', 'soju', 'makgeolli', 'takju', 'yakju',
  // Korean back labels
  '싱글', '몰트', '스카치', '위스키', '블렌디드', '사케', '준마이', '긴조', '다이긴조',
  '혼조조', '청주', '소주', '증류식', '희석식', '막걸리', '탁주', '약주', '과실주',
  '와인', '레드', '화이트', '로제', '스파클링', '샴페인', '리큐르', '맥주', '보드카',
  '브랜디', '꼬냑', '코냑', '원액', '숙성', '년', '년산', '알코올', '알콜', '용량',
  '제품명', '식품유형', '유형', '원재료명', '원재료', '제조원', '제조사', '수입원',
  '수입판매원', '수입자', '원산지', '주류', '주종', '주정', '정제수', '쌀', '누룩',
  '보리', '밀', '국내산', '수입산',
};

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

/// The label lines worth searching the catalog with, in label order, each
/// stripped of its kind words; a bracketed part is a line of its own. Drops strength and volume statements, bare
/// numbers, symbols, back-label paragraphs, company lines, lines of nothing
/// but kind words, and repeats.
List<String> labelSearchQueries(List<String> lines, {int limit = 6}) {
  final seen = <String>{};
  final queries = <String>[];
  final parts = lines
      .where((line) => !_companyLine.hasMatch(line))
      .expand((line) => line.split(_bracket));
  for (final raw in parts) {
    final line = raw.replaceAll(_whitespace, ' ').trim();
    if (line.length > 40) continue;
    if (_strengthOrVolumeLine.hasMatch(line)) continue;
    final words = line
        .split(' ')
        .map((word) => word.replaceAll(_edgePunctuation, ''))
        .where((word) => !_kindWords.contains(word.toLowerCase()))
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

/// What a label read found: the lines searched, and the drinks, likeliest
/// first.
class LabelSearch {
  const LabelSearch({
    required this.queries,
    required this.matches,
    this.backSide = false,
  });

  /// The product name of a back label, or the naming lines of a front one.
  /// Empty when the label held nothing to search with.
  final List<String> queries;
  final List<CatalogDrink> matches;

  /// The photo shows a back label: its fields, and no product name the
  /// catalog knows.
  final bool backSide;
}

/// A gateway answers at most this many queries a call.
const int _queriesPerCall = 8;
const int _maxQueries = 2 * _queriesPerCall;

/// Words a Korean back label carries and a front label does not.
final RegExp _backLabelWord = RegExp(
  r'원재료|식품\s*의?\s*유형|수입\s*(?:원|업)|반품|소비자\s*분쟁|품목\s*보고|내용량',
);

bool _isBackLabel(List<String> lines) {
  final text = lines.join(' ');
  return _backLabelWord.allMatches(text).map((m) => m[0]).toSet().length >= 2;
}

/// Finds the drink a label's [lines] name. A back label's product name is
/// searched alone; otherwise every naming line and pair of lines is, and
/// the drinks found are ordered by how much of each one's name the label
/// actually shows, so a line read wrong cannot outvote the name.
Future<LabelSearch> searchCatalogByLabel(
  CatalogSearchGateway gateway,
  List<String> lines, {
  int limit = 20,
}) async {
  final productName = labelProductName(lines);
  if (productName != null) {
    final hits = await _searchAll(gateway, productNameQueries(productName));
    // A back label's 제품명 field says the photo is a label and names the
    // drink, so what the search finds for it is taken as read.
    final matches = _rank(
      hits,
      <String>[productName],
      limit: limit,
      namedShare: 0,
    );
    if (matches.isNotEmpty) {
      return LabelSearch(queries: <String>[productName], matches: matches);
    }
  }
  final backSide = _isBackLabel(lines);
  final singles = labelSearchQueries(lines);
  if (singles.isEmpty) {
    return LabelSearch(
      queries: <String>[?productName],
      matches: const <CatalogDrink>[],
      backSide: backSide,
    );
  }
  final queries = <String>[
    ...singles,
    ...labelPairQueries(singles),
  ].take(_maxQueries).toList(growable: false);
  final hits = await _searchAll(gateway, queries);
  return LabelSearch(
    queries: singles,
    matches: _rank(
      hits,
      lines.where((line) => !_companyLine.hasMatch(line)).toList(),
      limit: limit,
    ),
    backSide: backSide,
  );
}

Future<List<List<CatalogDrink>>> _searchAll(
  CatalogSearchGateway gateway,
  List<String> queries,
) async {
  final calls = <Future<List<List<CatalogDrink>>>>[
    for (var i = 0; i < queries.length; i += _queriesPerCall)
      gateway.searchMany(
        queries.skip(i).take(_queriesPerCall).toList(growable: false),
        limit: catalogSearchPageSize,
        readOffLabel: true,
      ),
  ];
  return <List<CatalogDrink>>[
    for (final answers in await Future.wait(calls)) ...answers,
  ];
}

/// Orders the drinks the searches found: first by how much of the drink's
/// name the label shows, then by how many searches found it and how high.
/// Only a drink whose name the label shows at least [namedShare] of is a
/// candidate: a word or two that happen to be in a name (a keyboard's
/// "command" in Elderton Command Shiraz) name no drink, and a wrong drink
/// taken for the bottle does more harm than none.
List<CatalogDrink> _rank(
  List<List<CatalogDrink>> hits,
  List<String> labelLines, {
  required int limit,
  double namedShare = _namedShare,
}) {
  final label = _LabelText(labelLines);
  final votes = <String, int>{};
  final drinks = <String, CatalogDrink>{};
  for (final list in hits) {
    for (var rank = 0; rank < list.length; rank++) {
      final drink = list[rank];
      votes[drink.id] = (votes[drink.id] ?? 0) + (catalogSearchPageSize - rank);
      drinks.putIfAbsent(drink.id, () => drink);
    }
  }
  final shown = <String, _Shown>{
    for (final drink in drinks.values) drink.id: label.shows(drink),
  };
  final ids =
      drinks.keys
          .where((id) => shown[id]!.share >= namedShare)
          .toList(growable: false)
        ..sort((a, b) {
          final byName = shown[b]!.score.compareTo(shown[a]!.score);
          return byName != 0 ? byName : votes[b]!.compareTo(votes[a]!);
        });
  return ids.take(limit).map((id) => drinks[id]!).toList(growable: false);
}

/// The part of a drink's name a label must show for the drink to be one of
/// its candidates.
const double _namedShare = 0.5;

/// How much of a drink's name a label shows: [score] orders the candidates,
/// [share] is the part of the name's words that were read.
typedef _Shown = ({double score, double share});

final RegExp _apostrophe = RegExp("['’‘`´]");
final RegExp _wordRun = RegExp(r'[a-z]+|\d+|[가-힣]+|[぀-ヿ㐀-鿿]+');
final RegExp _latinRun = RegExp(r'^[a-z]+$');
final RegExp _digitRun = RegExp(r'^\d+$');
final RegExp _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);

const String _accented = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
const String _plain = 'aaaaaaceeeeiiiinooooouuuuyy';

/// Spellings an import label uses for a word the catalog writes one way.
const Map<String, String> _catalogSpelling = <String, String>{
  '레이블': '라벨',
  '카버네': '까베르네',
  '카베르네': '까베르네',
  '까베네': '까베르네',
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
String _fold(String text) {
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

const double _kindWordWeight = 0.25;

/// The text a label read holds, ready to be asked how much of a drink's
/// name it shows.
class _LabelText {
  _LabelText(List<String> lines) {
    for (final line in lines) {
      final folded = _fold(line);
      _squeezed.add(folded.replaceAll(_notLetterOrDigit, ''));
      String? before;
      for (final match in _wordRun.allMatches(folded)) {
        final word = match[0]!;
        if (_latinRun.hasMatch(word)) {
          _latin.add(word);
          // "T IPLE" is "TRIPLE" read with a gap.
          if (before != null) _latin.add('$before$word');
          before = word;
        } else {
          if (_digitRun.hasMatch(word)) _digits.add(word);
          before = null;
        }
      }
    }
  }

  final Set<String> _latin = <String>{};
  final Set<String> _digits = <String>{};
  final List<String> _squeezed = <String>[];

  /// How much of [drink]'s name the label shows: the matched words squared
  /// over the name's words, by the better of its Korean and English names,
  /// a kind word that is shown counting for a quarter.
  /// A name shown whole beats a longer name shown in part, and of two
  /// shown whole the longer wins.
  _Shown shows(CatalogDrink drink) {
    final korean = _showsName(drink.displayName);
    final english = _showsName(drink.nameEn ?? '');
    return korean.score >= english.score ? korean : english;
  }

  _Shown _showsName(String name) {
    var words = 0.0;
    var matched = 0.0;
    final seen = <String>{};
    for (final match in _wordRun.allMatches(_fold(name))) {
      final word = match[0]!;
      if (!seen.add(word)) continue;
      final double found;
      if (_digitRun.hasMatch(word)) {
        found = _digits.contains(word) ? 1 : 0;
      } else if (_latinRun.hasMatch(word)) {
        if (word.length < 3) continue;
        found = _latinMatch(word);
      } else {
        if (word.length < 2) continue;
        found = _squeezed.any((line) => line.contains(word))
            ? 1
            : _nearlyShown(word);
      }
      // "Scotch", "Whisky" are on every label of the kind; reading one
      // says little about which drink it is.
      words += 1;
      matched += found * (_kindWords.contains(word) ? _kindWordWeight : 1);
    }
    if (words == 0) return (score: 0, share: 0);
    return (score: matched * matched / words, share: matched / words);
  }

  /// Less than a whole match for a Korean word read one stroke off ("가쿠반"
  /// for 가쿠빈), which only a word of three syllables or more can afford.
  double _nearlyShown(String word) {
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

  /// 1 for the word as read; less for a read one or two letters off, which
  /// only a longer word can afford.
  double _latinMatch(String word) {
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
}

final RegExp _hangulRun = RegExp(r'^[가-힣]+$');

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
