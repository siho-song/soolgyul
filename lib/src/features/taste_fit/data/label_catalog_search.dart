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
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _edgePunctuation = RegExp(
  r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$',
  unicode: true,
);

/// The label lines worth searching the catalog with, in label order, each
/// stripped of its kind words. Drops strength and volume statements, bare
/// numbers, symbols, back-label paragraphs, lines of nothing but kind words,
/// and repeats.
List<String> labelSearchQueries(List<String> lines, {int limit = 6}) {
  final seen = <String>{};
  final queries = <String>[];
  for (final raw in lines) {
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

const int _hitsPerQuery = 10;

/// One catalog search per label line, merged into a single ranking: a drink
/// that several lines name outranks one a single line matched. Throws
/// [CatalogSearchException] only when every search failed.
Future<List<CatalogDrink>> searchCatalogByLabel(
  CatalogSearchGateway gateway,
  List<String> queries, {
  int limit = 20,
}) async {
  if (queries.isEmpty) return const <CatalogDrink>[];
  var failures = 0;
  final hits = await Future.wait(
    queries.map((query) async {
      try {
        return await gateway.search(query, limit: _hitsPerQuery);
      } on CatalogSearchException {
        failures += 1;
        return const <CatalogDrink>[];
      }
    }),
  );
  if (failures == queries.length) throw const CatalogSearchException();

  final scores = <String, int>{};
  final drinks = <String, CatalogDrink>{};
  for (final list in hits) {
    for (var rank = 0; rank < list.length; rank++) {
      final drink = list[rank];
      scores[drink.id] = (scores[drink.id] ?? 0) + (_hitsPerQuery - rank);
      drinks.putIfAbsent(drink.id, () => drink);
    }
  }
  final ids = drinks.keys.toList(growable: false)
    ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
  return ids.take(limit).map((id) => drinks[id]!).toList(growable: false);
}
