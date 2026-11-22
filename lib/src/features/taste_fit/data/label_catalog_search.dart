/// Finds the drinks a label photo shows: which lines are searched
/// (`label_queries.dart`), what the catalog answers, and how the drinks
/// found are weighed and decided (`label_score.dart`).
library;

import 'dart:math' as math;

import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import 'label_layout.dart';
import 'label_queries.dart';
import 'label_score.dart';

/// What a label read found: the lines searched, and the drinks, likeliest
/// first.
class LabelSearch {
  const LabelSearch({
    required this.queries,
    required this.matches,
    this.backSide = false,
    this.sure = false,
    this.tied = false,
    this.explained = const <String>[],
    this.share = 0,
    this.score = 0,
  });

  LabelSearch._ranked(
    this.queries,
    LabelRanking ranked, {
    this.backSide = false,
    bool? sure,
  }) : matches = ranked.matches,
       sure = sure ?? ranked.sure,
       tied = sure == null && ranked.tied,
       share = ranked.scores.firstOrNull?.share ?? 0,
       score = ranked.scores.firstOrNull?.total ?? 0,
       explained = <String>[
         for (final score in ranked.scores.take(8)) score.explain(),
         for (final drink in ranked.passedOver.take(5)) 'passed over: $drink',
       ];

  /// The product name of a back label, or the naming lines of a front one.
  /// Empty when the label held nothing to search with.
  final List<String> queries;
  final List<CatalogDrink> matches;

  /// The photo shows a back label: its fields, and no product name the
  /// catalog knows.
  final bool backSide;

  /// The label shows most of the likeliest drink's name, a word of its own
  /// letter for letter: enough to list the drink without asking. A brand
  /// whose bottle was not told apart ("MONTES ALPHA" alone) is not.
  final bool sure;

  /// The label names a brand and not which bottle of it: [matches] starts
  /// with bottles the label shows equally much of, in no order that says
  /// which one it is.
  final bool tied;

  /// Why the drinks stand in this order: a line per drink with what the
  /// label showed of it. For reading a result, never shown to a member.
  final List<String> explained;

  /// How much of the likeliest drink's name the label shows, 0 to 1.
  final double share;

  /// The likeliest drink's score: everything the label says of it.
  final double score;
}

/// A gateway answers at most this many queries a call.
const int _queriesPerCall = 8;
const int _maxQueries = 2 * _queriesPerCall;

/// Finds the drink a label's [lines] name. A back label's product name is
/// searched alone; otherwise every naming line and pair of lines is, and
/// the drinks found are weighed by what the label says of each
/// ([rankLabelCandidates]), so a line read wrong cannot outvote the name.
///
/// [searchFirst] is the same lines in the order to pick the searches from
/// (a label's largest letters first); without it they are picked from the
/// top. [nameTiers], [tagLines] and [surelyRead] are passed on to the
/// weighing.
Future<LabelSearch> searchCatalogByLabel(
  CatalogSearchGateway gateway,
  List<String> lines, {
  int limit = 20,
  List<String>? searchFirst,
  List<List<String>>? nameTiers,
  List<String> tagLines = const <String>[],
  List<String>? surelyRead,
  LabelWeights weights = const LabelWeights(),
}) async {
  final productName = labelProductName(lines);
  if (productName != null) {
    final ranked = rankLabelCandidates(
      await _searchAll(gateway, productNameQueries(productName)),
      labelLines: <String>[productName],
      trustSearch: true,
      limit: limit,
      weights: weights,
    );
    if (ranked.matches.isNotEmpty) {
      return LabelSearch._ranked(<String>[productName], ranked, sure: true);
    }
  }
  final backSide = isBackLabel(lines);
  final singles = searchFirst == null
      ? labelSearchQueries(lines)
      : labelSearchQueries(searchFirst, limit: _queriesPerCall);
  if (singles.isEmpty) {
    return LabelSearch(
      queries: <String>[?productName],
      matches: const <CatalogDrink>[],
      backSide: backSide,
    );
  }
  final queries = <String>[
    ...singles,
    // Largest first, the first line is the name: each other line is tried
    // with it ("VIU MANENT" with "CABERNET SAUVIGNON").
    if (searchFirst == null)
      ...labelPairQueries(singles)
    else
      for (final other in singles.skip(1)) '${singles.first} $other',
  ].take(_maxQueries).toList(growable: false);
  bool names(String line) => !isCompanyLine(line);
  final ranked = rankLabelCandidates(
    await _searchAll(gateway, queries),
    labelLines: lines.where(names).toList(growable: false),
    nameTiers: nameTiers,
    tagLines: tagLines,
    surelyRead: surelyRead?.where(names).toList(growable: false),
    limit: limit,
    weights: weights,
  );
  return LabelSearch._ranked(singles, ranked, backSide: backSide);
}

/// One drink a photo shows: the lines that name it and what the catalog
/// has for them, likeliest first.
class LabelFind {
  const LabelFind({required this.group, required this.search});

  final LabelGroup group;
  final LabelSearch search;

  CatalogDrink get drink => search.matches.first;
}

/// What a photo read found: every drink it shows, in reading order.
class PhotoSearch {
  const PhotoSearch({
    required this.finds,
    required this.queries,
    this.backSide = false,
    this.unnamed = const <LabelFind>[],
  });

  final List<LabelFind> finds;

  /// The labels and list entries that were searched and name no drink,
  /// kept for reading why ([LabelSearch.explained]).
  final List<LabelFind> unnamed;

  /// The drink nearest the middle of the photo, which is the bottle the
  /// photo was taken of; `null` when the photo shows no drink.
  LabelFind? get main => finds.isEmpty
      ? null
      : finds.reduce((a, b) => b.group.offCentre < a.group.offCentre ? b : a);

  /// What to show for the photo, in reading order: [main] and every other
  /// drink it surely shows. One is a drink to ask about with its
  /// candidates; more are a list, in which a [main] whose brand was read
  /// and whose kind was not ([LabelSearch.tied]) brings its brand's
  /// bottles to choose from.
  List<LabelFind> get listed {
    final main = this.main;
    return finds
        .where((find) => identical(find, main) || find.search.sure)
        .toList(growable: false);
  }

  /// Every line searched, in the order searched. Empty when the photo held
  /// nothing to search with.
  final List<String> queries;

  /// A back label that names no drink the catalog knows.
  final bool backSide;
}

/// A price as a shelf tag prints it ("39,000", "13, 900").
final RegExp _tagPrice = RegExp(r'\d{1,3}(?:,\s?\d{3})+');

/// The price tag a shelf puts under a bottle: the nearest block below
/// [label] that states a price and shares at least half its width, or the
/// tag's, with it.
LabelGroup? _tagUnder(LabelGroup label, List<LabelGroup> labels) {
  LabelGroup? nearest;
  for (final other in labels) {
    if (other.top < label.bottom) continue;
    if (!other.lines.any((line) => _tagPrice.hasMatch(line.text))) continue;
    final shared =
        math.min(label.right, other.right) - math.max(label.left, other.left);
    final narrower = math.min(
      label.right - label.left,
      other.right - other.left,
    );
    if (shared < 0.5 * narrower) continue;
    if (nearest == null || other.top < nearest.top) nearest = other;
  }
  return nearest;
}

/// A line the reader was at least this sure of states the strength it
/// seems to.
const double _sureRead = 0.5;

/// List lines are searched this many a call: a line is a whole name, and a
/// call of long names is slow.
const int _listLinesPerCall = 4;

/// Finds every drink the photo shows. The lines are split into the labels
/// and list entries they belong to ([groupLines]); each label is searched
/// by its largest lines and each list entry by itself, and a drink found
/// twice (a label and its price tag, a menu's Korean and English line) is
/// kept once.
Future<PhotoSearch> searchCatalogByPhoto(
  CatalogSearchGateway gateway,
  List<ReadLine> read, {
  int limit = 20,
  LabelWeights weights = const LabelWeights(),
}) async {
  final groups = groupLines(read);
  final labels = groups.where((group) => !group.listEntry).toList();
  final entries = groups.where((group) => group.listEntry).toList();

  final labelSearches = Future.wait(<Future<LabelSearch?>>[
    for (final label in labels)
      _orNull(
        () => searchCatalogByLabel(
          gateway,
          label.lines.map((line) => line.text).toList(growable: false),
          searchFirst: label.largestFirst
              .map((line) => line.text)
              .toList(growable: false),
          nameTiers: <List<String>>[
            for (final tier in label.nameTiers)
              tier.map((line) => line.text).toList(growable: false),
          ],
          tagLines: <String>[
            for (final line in _tagUnder(label, labels)?.lines ?? const [])
              line.text,
          ],
          surelyRead: <String>[
            for (final line in label.lines)
              if (line.confidence >= _sureRead) line.text,
          ],
          limit: limit,
          weights: weights,
        ),
      ),
  ]);
  final entrySearches = _orNull(
    () => _searchListEntries(gateway, entries, limit: limit, weights: weights),
  );

  final answered = await labelSearches;
  final listed = await entrySearches;
  // One block's search failing leaves the others' drinks to show; the
  // photo's search fails only when every search it ran did.
  final ran = labels.length + (entries.isEmpty ? 0 : 1);
  final failed =
      answered.where((search) => search == null).length +
      (listed == null ? 1 : 0);
  if (ran > 0 && failed == ran) throw const CatalogSearchException();
  final searched =
      <(LabelGroup, LabelSearch)>[
        for (final (index, search) in answered.indexed)
          if (search != null) (labels[index], search),
        ...?listed,
      ]..sort((a, b) {
        final down = a.$1.top.compareTo(b.$1.top);
        return down != 0 ? down : a.$1.left.compareTo(b.$1.left);
      });

  final found = <String>{};
  final finds = <LabelFind>[
    for (final (group, search) in searched)
      if (search.matches.isNotEmpty && found.add(search.matches.first.id))
        LabelFind(group: group, search: search),
  ];
  return PhotoSearch(
    finds: finds,
    queries: <String>[for (final (_, search) in searched) ...search.queries],
    backSide: finds.isEmpty && searched.any((pair) => pair.$2.backSide),
    unnamed: <LabelFind>[
      for (final (group, search) in searched)
        if (search.matches.isEmpty) LabelFind(group: group, search: search),
    ],
  );
}

Future<T?> _orNull<T>(Future<T> Function() search) async {
  try {
    return await search();
  } on CatalogSearchException {
    return null;
  }
}

/// Searches each list line by itself. A line right under another that
/// finds the same drinks is the same entry again (the name in a second
/// language), so the two are one entry, ranked by both lines.
Future<List<(LabelGroup, LabelSearch)>> _searchListEntries(
  CatalogSearchGateway gateway,
  List<LabelGroup> entries, {
  required int limit,
  required LabelWeights weights,
}) async {
  final names = <String>[
    for (final entry in entries) listEntryName(entry.lines.single.text),
  ];
  final queries = <List<String>>[
    for (final name in names)
      labelSearchQueries(<String>[name], limit: 2, maxLength: 80),
  ];
  final flat = <String>[for (final list in queries) ...list];
  final calls = <Future<List<List<CatalogDrink>>>>[
    for (var i = 0; i < flat.length; i += _listLinesPerCall)
      gateway.searchMany(
        flat.skip(i).take(_listLinesPerCall).toList(growable: false),
        limit: catalogSearchPageSize,
        readOffLabel: true,
      ),
  ];
  final hits = <List<CatalogDrink>>[
    for (final answers in await Future.wait(calls)) ...answers,
  ];
  final found = <_ListEntry>[];
  var at = 0;
  for (var index = 0; index < entries.length; index++) {
    final own = hits.sublist(at, at + queries[index].length);
    at += queries[index].length;
    final entry = _ListEntry(
      lines: entries[index].lines,
      names: <String>[names[index]],
      queries: queries[index],
      hits: own,
    )..rank(limit, weights);
    // A price or a heading between the two lines found nothing and is no
    // entry to compare with.
    final before = found
        .where((earlier) => earlier.matches.isNotEmpty)
        .lastOrNull;
    if (before != null && before.repeatedBy(entry)) {
      before
        ..lines.addAll(entry.lines)
        ..names.addAll(entry.names)
        ..queries.addAll(entry.queries)
        ..hits.addAll(entry.hits)
        ..rank(limit, weights);
    } else {
      found.add(entry);
    }
  }
  return <(LabelGroup, LabelSearch)>[
    for (final entry in found)
      (
        LabelGroup(lines: entry.lines, listEntry: true),
        LabelSearch._ranked(entry.queries, entry.ranked),
      ),
  ];
}

class _ListEntry {
  _ListEntry({
    required List<ReadLine> lines,
    required List<String> names,
    required List<String> queries,
    required List<List<CatalogDrink>> hits,
  }) : lines = <ReadLine>[...lines],
       names = <String>[...names],
       queries = <String>[...queries],
       hits = <List<CatalogDrink>>[...hits];

  final List<ReadLine> lines;
  final List<String> names;
  final List<String> queries;
  final List<List<CatalogDrink>> hits;
  LabelRanking ranked = LabelRanking.none;

  List<CatalogDrink> get matches => ranked.matches;

  void rank(int limit, LabelWeights weights) {
    ranked = rankLabelCandidates(
      hits,
      labelLines: names,
      limit: limit,
      weights: weights,
    );
  }

  /// Whether [next] sits right under this entry and found one of the
  /// drinks this entry found first.
  bool repeatedBy(_ListEntry next) {
    final above = lines.last;
    final below = next.lines.first;
    if (below.top - above.bottom > math.max(above.height, below.height)) {
      return false;
    }
    final mine = matches.take(3).map((drink) => drink.id).toSet();
    return next.matches.take(3).any((drink) => mine.contains(drink.id));
  }
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
