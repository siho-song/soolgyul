/// Ranks the drinks a label photo may show and says how sure the first is.
///
/// The catalog answers the words read with the drinks whose name words look
/// like them ([LabelCandidate]); the line search ([searchCatalogByPhoto])
/// answers what it made of the label. For each drink this measures what
/// the label shows of it (its rare name words read exactly or a few letters
/// off, its producer, place, grapes, age, kind, what the line search made
/// of it) and a learned ranker orders the drinks; a learned decision then
/// says whether the first is sure, its brand alone is, or neither. Both were
/// learned from labelled photos with these same measures
/// (`label_match_model.g.dart`).
library;

import 'dart:math' as math;

import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import 'label_catalog_search.dart';
import 'label_layout.dart';
import 'label_match_model.g.dart';
import 'label_match_tables.g.dart';

/// What the line search made of the label: the drinks one search found,
/// likeliest first, and whether it showed them first, called the first
/// sure, or found a brand without its bottle.
class LineFind {
  const LineFind({
    required this.names,
    this.first = false,
    this.sure = false,
    this.tied = false,
  });

  /// The drinks' Korean names, years left off.
  final List<String> names;
  final bool first;
  final bool sure;
  final bool tied;
}

enum LabelMatchState {
  /// The first drink is the one: shown without asking.
  sure,

  /// The first drinks are one producer's, which the label names, and which
  /// of its bottles is not sure.
  brand,

  /// Candidates, likeliest first.
  unsure,

  /// Nothing the label shows names a drink.
  none,
}

class LabelMatch {
  const LabelMatch({
    required this.drinks,
    required this.state,
    this.sureness = 0,
  });

  static const LabelMatch nothing = LabelMatch(
    drinks: <CatalogDrink>[],
    state: LabelMatchState.none,
  );

  /// One a drink (its years are one drink), likeliest first.
  final List<CatalogDrink> drinks;
  final LabelMatchState state;

  /// How likely the first drink is the one, 0 to 1.
  final double sureness;
}

// --- folding -------------------------------------------------------------

final RegExp _notKept = RegExp(r'[^0-9a-z぀-ヿ㐀-鿿가-힣]+');
final RegExp _yearAtEnd = RegExp(r'\s+(?:19|20)\d\d$');

bool _isMark(int rune) =>
    (rune >= 0x300 && rune <= 0x36f) ||
    (rune >= 0x1ab0 && rune <= 0x1aff) ||
    (rune >= 0x1dc0 && rune <= 0x1dff) ||
    (rune >= 0x20d0 && rune <= 0x20ff) ||
    (rune >= 0xfe20 && rune <= 0xfe2f) ||
    rune == 0x3099 ||
    rune == 0x309a;

/// [text] as the match compares it, as the catalog search folds it: lower
/// case, accents and voicing marks off, apostrophes dropped, anything but
/// letters and digits one space.
String labelMatchFold(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final folded = labelMatchCharFolds[rune];
    if (folded != null) {
      out.write(folded);
    } else if (!_isMark(rune)) {
      out.write(String.fromCharCode(rune).toLowerCase());
    }
  }
  return out
      .toString()
      .replaceAll('’', '')
      .replaceAll("'", '')
      .replaceAll(_notKept, ' ')
      .trim();
}

List<String> labelMatchWords(String text) {
  final folded = labelMatchFold(text);
  return folded.isEmpty ? const <String>[] : folded.split(' ');
}

/// A drink's name as one drink: its years are the same drink.
String drinkOfName(String name) => name.trim().replaceAll(_yearAtEnd, '');

// --- reading -------------------------------------------------------------

class _Token {
  const _Token(this.word, this.height);
  final String word;
  final int height;
}

int _heightKey(double height) => (height * 10000).round();

/// Each word read, and each two neighbouring words written as one, with the
/// height of its line.
List<_Token> _tokens(List<ReadLine> lines) => <_Token>[
  for (final line in lines)
    ...() {
      final words = labelMatchWords(line.text);
      final height = _heightKey(line.height);
      return <_Token>[
        for (var j = 0; j < words.length; j++) ...<_Token>[
          _Token(words[j], height),
          if (j + 1 < words.length) _Token(words[j] + words[j + 1], height),
        ],
      ];
    }(),
];

/// The words to ask the catalog with: those of three letters or more that
/// are not numbers, once each.
List<String> labelMatchQueryWords(List<ReadLine> lines) {
  final out = <String>{};
  for (final token in _tokens(lines)) {
    if (token.word.length < 3 || _digits.hasMatch(token.word)) continue;
    out.add(token.word);
    if (out.length == 120) break;
  }
  return out.toList(growable: false);
}

final RegExp _digits = RegExp(r'^\d+$');

// --- comparing words -----------------------------------------------------

/// Letters a text reader takes for one another: compared after this, a swap
/// between them costs nothing.
const Map<String, String> _ocrSame = <String, String>{
  '0': 'o', 'q': 'o', 'd': 'o', '1': 'i', 'l': 'i', 'j': 'i', '!': 'i', //
  '|': 'i', '5': 's', '8': 'b', '6': 'g', 'c': 'e', 'u': 'v', 'y': 'v',
  'k': 'x', 'h': 'n', 'f': 't', 'z': '2',
};

String _ocrCanon(String word) {
  final joined = word
      .replaceAll('rn', 'm')
      .replaceAll('vv', 'w')
      .replaceAll('cl', 'd');
  final out = StringBuffer();
  for (final rune in joined.runes) {
    final char = String.fromCharCode(rune);
    out.write(_ocrSame[char] ?? char);
  }
  return out.toString();
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

double _likeness(String a, String b) {
  final longest = math.max(a.length, b.length);
  return longest == 0 ? 1 : 1 - _levenshtein(a, b) / longest;
}

/// The least likeness a read word must have to a name word to count, for a
/// match letter for letter and for one a few letters off as read.
const double _ocrLeast = 0.8;

/// How a name word was read: letter for letter (1 or 0), a few letters off
/// as a reader misreads (0.8 to 1, else 0), and whether so in one of the
/// label's two largest sizes of letters.
class _WordRead {
  _WordRead(this.exact, this.ocr, this.big);
  final double exact;
  final double ocr;
  final bool big;
}

// --- facts read off the label -------------------------------------------

final RegExp _ageRead = RegExp(
  r'(?<!\d)(\d{1,2})\s*(?:years?|yrs?|yo|y o|ans|anos|anni|jahre|년)(?![0-9a-z぀-ヿ㐀-鿿가-힣])',
);
final RegExp _strengthRead = RegExp(r'(?<![\d.])(\d{1,2}(?:[.,]\d{1,2})?)\s*%');

/// Words that say which kind of drink a label is on.
const Map<String, List<String>> _kindSaid = <String, List<String>>{
  'whisky': <String>[
    'whisky', 'whiskey', 'scotch', 'bourbon', 'single malt', //
    'blended malt', 'rye whiskey', 'distillery', '위스키',
  ],
  'wine': <String>[
    'wine', 'vin', 'vino', 'wein', 'chateau', 'domaine', 'appellation', //
    'cuvee', 'vintage', 'doc', 'docg', 'aoc', 'reserva', 'riserva',
    'grand cru', 'champagne', 'brut', 'cabernet', 'merlot', 'chardonnay',
    'pinot', 'sauvignon', '와인',
  ],
  'sake': <String>[
    'sake', 'junmai', 'ginjo', 'daiginjo', '純米', '吟醸', '日本酒', '清酒', //
    '本醸造', '酒造', '사케',
  ],
  'korean_traditional': <String>[
    '소주', '막걸리', '약주', '탁주', '증류주', '전통주', '청주', 'soju', //
    'makgeolli',
  ],
};

final List<String> _grapePhrases = <String>{
  for (final names in labelMatchGrapeNames.values) ...names,
}.where((phrase) => phrase.length > 3).toList(growable: false);

/// Whether [needle] stands in [text] as a whole or nearly so: rapidfuzz's
/// partial ratio, the best likeness of [needle] to a stretch of [text] its
/// length (or shorter at either end), at least [least] of 100.
bool _nearlyIn(String needle, String text, double least) {
  if (needle.isEmpty) return false;
  if (needle.length > text.length) {
    return _ratio(needle, text) >= least;
  }
  final length = needle.length;
  final shortest = (length * least / (200 - least)).ceil();
  bool check(String window) => _ratio(needle, window) >= least;
  for (var size = shortest; size < length; size++) {
    if (check(text.substring(0, size))) return true;
    if (check(text.substring(text.length - size))) return true;
  }
  final need = <int, int>{};
  for (final unit in needle.codeUnits) {
    need[unit] = (need[unit] ?? 0) + 1;
  }
  final have = <int, int>{};
  var shared = 0;
  void add(int unit, int by) {
    final before = math.min(have[unit] ?? 0, need[unit] ?? 0);
    have[unit] = (have[unit] ?? 0) + by;
    shared += math.min(have[unit]!, need[unit] ?? 0) - before;
  }

  final least2 = least / 100 * length;
  for (var i = 0; i < text.length; i++) {
    add(text.codeUnitAt(i), 1);
    if (i >= length) add(text.codeUnitAt(i - length), -1);
    if (i >= length - 1 &&
        shared >= least2 &&
        check(text.substring(i - length + 1, i + 1))) {
      return true;
    }
  }
  return false;
}

/// Indel likeness, 0 to 100: twice the longest common subsequence over
/// both lengths.
double _ratio(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 100;
  var previous = List<int>.filled(b.length + 1, 0);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      current[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
          ? previous[j - 1] + 1
          : math.max(previous[j], current[j - 1]);
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return 200 * previous[b.length] / (a.length + b.length);
}

// --- the measures --------------------------------------------------------

class _Row {
  _Row(this.candidate, this.measures);
  final LabelCandidate candidate;
  final Map<String, double> measures;
  late final String drink = drinkOfName(candidate.drink.displayName);
  List<String> producer = const <String>[];
}

/// The most a word says: a word of a name no other name holds.
const double _rarest = 10.81;

/// Measures every candidate against the label read as [lines].
List<_Row> _measure(
  List<ReadLine> lines,
  List<LabelCandidate> candidates,
  List<LineFind> lineFinds,
) {
  final tokens = _tokens(lines);
  if (tokens.isEmpty || candidates.isEmpty) return const <_Row>[];
  final text = ' ${lines.map((line) => labelMatchFold(line.text)).join(' ')} ';
  final heights = <int>{
    for (final line in lines) _heightKey(line.height),
  }.toList()..sort((a, b) => b.compareTo(a));
  final bigLetters = heights.take(2).toSet();

  final readAges = <int>{
    for (final match in _ageRead.allMatches(text)) int.parse(match[1]!),
  };
  final readStrengths = <double>[
    // read off the lines as printed: folding drops the "%"
    for (final match in _strengthRead.allMatches(
      lines.map((line) => line.text).join(' '),
    ))
      double.parse(match[1]!.replaceAll(',', '.')),
  ];
  final readGrapes = <String>{
    for (final phrase in _grapePhrases)
      if (text.contains(' $phrase ')) phrase,
  };
  final readKinds = <String>{
    for (final MapEntry(key: kind, value: words) in _kindSaid.entries)
      if (words.any(
        (word) =>
            text.contains(' $word ') ||
            (word.length > 1 &&
                word.codeUnits.any((unit) => unit > 127) &&
                text.contains(word)),
      ))
        kind,
  };

  // the line search's finds
  final lineRank = <String, int>{};
  final lineFirst = <String>{};
  final lineSure = <String>{};
  final lineTied = <String>{};
  for (final find in lineFinds) {
    for (final (rank, name) in find.names.indexed) {
      lineRank[name] = math.min(lineRank[name] ?? 9, rank);
    }
    if (find.names.isEmpty) continue;
    if (find.first) lineFirst.add(find.names.first);
    if (find.sure) lineSure.add(find.names.first);
    if (find.tied) lineTied.addAll(find.names);
  }

  // how each name word was read, once a word
  final canonTokens = <String>[
    for (final token in tokens) _ocrCanon(token.word),
  ];
  final wordRead = <String, _WordRead>{};
  _WordRead read(String word) => wordRead.putIfAbsent(word, () {
    var exact = 0.0;
    var ocr = 0.0;
    var big = false;
    final canon = _ocrCanon(word);
    for (final (index, token) in tokens.indexed) {
      double seen;
      if (token.word == word) {
        exact = 1;
        seen = 1;
      } else if (word.length > 3 && token.word.length > 2) {
        final like = _likeness(canon, canonTokens[index]);
        seen = like >= _ocrLeast ? like : 0;
      } else {
        seen = 0;
      }
      if (seen > ocr) ocr = seen;
      if (seen > 0 && bigLetters.contains(token.height)) big = true;
    }
    return _WordRead(exact, ocr, big);
  });

  final rows = <_Row>[];
  for (final candidate in candidates) {
    final drink = candidate.drink;
    final facts = drink.labelFacts;
    final m = <String, double>{};
    Map<String, double>? best;
    for (final name in <String?>[drink.nameEn, drink.displayName]) {
      final words = labelMatchWords((name ?? '').replaceAll(_yearAtEnd, ''));
      if (words.isEmpty) continue;
      final side = _sideMeasures(words, candidate.nameRarity, read);
      if (best == null || side['mass_ocr']! > best['mass_ocr']!) best = side;
    }
    m.addAll(best ?? _emptySide);
    final producer = <String>{
      for (final name in facts?.producer ?? const <String>[])
        if (labelMatchFold(name).isNotEmpty) labelMatchFold(name),
    }.toList()..sort();
    m['producer'] =
        producer.any(
          (name) =>
              name.length > 3 &&
              (text.contains(' $name ') || _nearlyIn(name, text, 92)),
        )
        ? 1
        : 0;
    var place = 0.0;
    for (final (depth, names) in (facts?.regions ?? const []).indexed) {
      for (final raw in names) {
        final name = labelMatchFold(raw);
        if (name.length > 3 && text.contains(' $name ')) {
          place = math.max(place, math.pow(0.5, depth).toDouble());
        }
      }
    }
    m['place'] = place;
    final own = <String>{
      for (final key in facts?.grapes ?? const <String>[])
        ...?labelMatchGrapeNames[key],
    };
    final grapeRead = own.any(readGrapes.contains);
    m['grape'] = grapeRead ? 1 : 0;
    m['grape_other'] = readGrapes.isNotEmpty && !grapeRead ? 1 : 0;
    final abv = drink.abvPercent;
    final strengthRead =
        abv != null && readStrengths.any((read) => (read - abv).abs() <= 0.5);
    m['abv'] = strengthRead ? 1 : 0;
    m['abv_other'] = abv != null && readStrengths.isNotEmpty && !strengthRead
        ? 1
        : 0;
    final age = facts?.ageYears?.round();
    m['age'] = age != null && readAges.contains(age) ? 1 : 0;
    m['age_other'] =
        age != null && readAges.isNotEmpty && !readAges.contains(age) ? 1 : 0;
    m['age_unread'] = age != null && readAges.isEmpty ? 1 : 0;
    final kind = candidate.kind;
    m['kind_read'] = readKinds.contains(kind) ? 1 : 0;
    m['kind_other'] = readKinds.isNotEmpty && !readKinds.contains(kind) ? 1 : 0;
    m['known'] = facts?.known == true ? 1 : 0;
    m['staple'] = facts?.staple == true ? 1 : 0;
    m['pool'] = candidate.found;
    final row = _Row(candidate, m)..producer = producer;
    final name = row.drink;
    m['app_in'] = lineRank.containsKey(name) ? 1 : 0;
    m['app_rank'] = lineRank.containsKey(name) ? 1 / (1 + lineRank[name]!) : 0;
    m['app_first'] = lineFirst.contains(name) ? 1 : 0;
    m['app_sure'] = lineSure.contains(name) ? 1 : 0;
    m['app_tied'] = lineTied.contains(name) ? 1 : 0;
    rows.add(row);
  }
  return _onePerDrink(rows);
}

const Map<String, double> _emptySide = <String, double>{
  'mass_exact': 0, 'cov_exact': 0, 'miss_exact': 0, 'maxw_exact': 0, //
  'mass_ocr': 0, 'cov_ocr': 0, 'miss_ocr': 0, 'maxw_ocr': 0, 'big': 0,
};

/// What the label shows of one of a drink's names ([words]): the rare
/// words read, summed by how much each says, as a share of the name, what
/// is left unread, and the rarest word read.
Map<String, double> _sideMeasures(
  List<String> words,
  Map<String, double> rarity,
  _WordRead Function(String) read,
) {
  final weight = <double>[
    for (final word in words)
      (rarity[word] ?? _rarest) *
          (labelMatchKindWords.contains(word) ? 0.25 : 1),
  ];
  final total = weight.fold(0.0, (sum, w) => sum + w);
  final out = <String, double>{};
  for (final way in const <String>['exact', 'ocr']) {
    var mass = 0.0;
    var most = 0.0;
    for (final (index, word) in words.indexed) {
      final seen = way == 'exact' ? read(word).exact : read(word).ocr;
      mass += weight[index] * seen;
      if (seen > 0) most = math.max(most, weight[index]);
    }
    out['mass_$way'] = mass;
    out['cov_$way'] = total > 0 ? mass / total : 0;
    out['miss_$way'] = total - mass;
    out['maxw_$way'] = most;
  }
  var big = 0.0;
  for (final (index, word) in words.indexed) {
    if (read(word).big) big += weight[index];
  }
  out['big'] = total > 0 ? big / total : 0;
  return out;
}

/// A drink's years are one drink: one row a drink, the one the label says
/// most for.
List<_Row> _onePerDrink(List<_Row> rows) {
  final best = <String, _Row>{};
  double say(_Row row) => row.measures['mass_ocr']! + row.measures['abv']!;
  for (final row in rows) {
    final kept = best[row.drink];
    if (kept == null || say(row) > say(kept)) best[row.drink] = row;
  }
  return best.values.toList(growable: false);
}

// --- the models ----------------------------------------------------------

List<List<double>> _inputs(List<_Row> rows) {
  final plain = <List<double>>[
    for (final row in rows)
      <double>[for (final name in labelRankerFeatures) row.measures[name]!],
  ];
  final most = <String, double>{
    for (final name in labelRankerRelative)
      name: rows.map((row) => row.measures[name]!).reduce(math.max),
  };
  return <List<double>>[
    for (final (index, row) in rows.indexed)
      <double>[
        ...plain[index],
        for (final name in labelRankerRelative)
          row.measures[name]! - most[name]!,
      ],
  ];
}

/// The ranker's probability that the drink of [input] is the one.
double labelRankerScore(List<double> input) {
  var raw = labelRankerBaseline;
  for (final tree in labelRankerTrees) {
    var node = 0;
    while (tree[node * 7 + 5] == 0) {
      final value = input[tree[node * 7].toInt()];
      final left = value.isNaN
          ? tree[node * 7 + 6] == 1
          : value <= tree[node * 7 + 1];
      node = (left ? tree[node * 7 + 2] : tree[node * 7 + 3]).toInt();
    }
    raw += tree[node * 7 + 4];
  }
  return 1 / (1 + math.exp(-raw));
}

/// The decision's probability that the first drink is the one.
double labelSureScore(List<double> input) {
  var raw = labelSureBias;
  for (var i = 0; i < input.length; i++) {
    raw +=
        labelSureWeights[i] * (input[i] - labelSureMean[i]) / labelSureScale[i];
  }
  return 1 / (1 + math.exp(-raw));
}

/// Ranks [candidates] for the label read as [lines] and decides how sure
/// the first is. [lineFinds] is what the line search made of the same
/// label; [cut] says the lines are of one bottle cut out of a photo of
/// several, not of a whole photo.
LabelMatch rankLabelMatch(
  List<ReadLine> lines,
  List<LabelCandidate> candidates, {
  List<LineFind> lineFinds = const <LineFind>[],
  bool cut = false,
}) {
  final rows = _measure(lines, candidates, lineFinds);
  if (rows.isEmpty) return LabelMatch.nothing;
  final inputs = _inputs(rows);
  final scores = <double>[for (final input in inputs) labelRankerScore(input)];
  final order = List<int>.generate(rows.length, (i) => i)
    ..sort((a, b) {
      final by = scores[b].compareTo(scores[a]);
      return by != 0 ? by : a.compareTo(b);
    });
  final first = rows[order.first].measures;
  final sureness = labelSureScore(<double>[
    scores[order[0]],
    scores[order[0]] - (order.length > 1 ? scores[order[1]] : 0),
    rows.length.toDouble(),
    cut ? 1 : 0,
    first['app_sure']!,
    first['app_first']!,
    first['cov_ocr']!,
    first['maxw_ocr']!,
    first['producer']!,
    first['kind_other']!,
    first['age_other']!,
  ]);
  final top = <_Row>[for (final index in order.take(3)) rows[index]];
  final oneMaker =
      top.first.producer.isNotEmpty &&
      top.every(
        (row) => row.producer.join('|') == top.first.producer.join('|'),
      );
  final state = sureness >= labelSureThreshold
      ? LabelMatchState.sure
      : oneMaker && first['producer'] == 1
      ? LabelMatchState.brand
      : LabelMatchState.unsure;
  return LabelMatch(
    drinks: <CatalogDrink>[
      for (final index in order) rows[index].candidate.drink,
    ],
    state: state,
    sureness: sureness,
  );
}

/// Every drink's measures, one a drink, for checking the port against the
/// models' training.
Map<String, Map<String, double>> labelMatchMeasures(
  List<ReadLine> lines,
  List<LabelCandidate> candidates, {
  List<LineFind> lineFinds = const <LineFind>[],
}) => <String, Map<String, double>>{
  for (final row in _measure(lines, candidates, lineFinds))
    row.drink: row.measures,
};

/// What the line search made of the photo, as the models learned it: for a
/// whole photo, the drinks it lists ([PhotoSearch.listed], the first of
/// them first) and those it found and does not list; for a bottle cut out
/// of a photo, every drink it found, the one nearest the middle first.
List<LineFind> lineFindsOf(PhotoSearch photo, {bool cut = false}) {
  List<String> names(LabelFind find) => <String>[
    for (final drink in find.search.matches.take(5))
      drinkOfName(drink.displayName),
  ];
  if (cut) {
    final main = photo.main;
    return <LineFind>[
      for (final find in photo.finds)
        LineFind(
          names: names(find),
          first: identical(find, main),
          sure: find.search.sure,
          tied: find.search.tied,
        ),
    ];
  }
  final listed = photo.listed;
  return <LineFind>[
    for (final (index, find) in listed.indexed)
      LineFind(
        names: names(find),
        first: index == 0,
        sure: find.search.sure,
        tied: find.search.tied,
      ),
    for (final find in photo.finds)
      if (!listed.contains(find)) LineFind(names: names(find)),
  ];
}

/// Ranks the drinks the photo read as [lines] may show, from the drinks
/// [catalog] answers its words with and those [lineSearch] found, and says
/// how sure the first is. [cut] as for [rankLabelMatch].
Future<LabelMatch> matchLabelPhoto(
  LabelWordSearch catalog,
  List<ReadLine> lines,
  PhotoSearch lineSearch, {
  bool cut = false,
}) async {
  final words = labelMatchQueryWords(lines);
  final alsoIds = <String>{
    for (final find in lineSearch.finds)
      for (final drink in find.search.matches.take(5)) drink.id,
  }.take(40).toList(growable: false);
  if (words.isEmpty && alsoIds.isEmpty) return LabelMatch.nothing;
  final candidates = await catalog.searchByLabelWords(words, alsoIds: alsoIds);
  return rankLabelMatch(
    lines,
    candidates,
    lineFinds: lineFindsOf(lineSearch, cut: cut),
    cut: cut,
  );
}
