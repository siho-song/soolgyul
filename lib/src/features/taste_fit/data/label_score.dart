/// Weighs the drinks a label's searches found and decides what the label
/// shows: the second and third of the label search's three steps (find
/// candidates, weigh them, decide).
///
/// A drink's score is a sum of items, each one thing the label says for
/// or against it, so a result can be read item by item
/// ([LabelScore.explain]) and one item changed without touching the rest.
/// The numbers are in [LabelWeights] and the words' weights in
/// `label_words.dart`.
library;

import 'dart:math' as math;

import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import 'label_text.dart';
import 'label_words.dart';

/// The numbers the label search weighs and decides by. A change here is
/// measured with `dart run tools/label_bench/label_bench.dart`.
class LabelWeights {
  const LabelWeights({
    this.facts = 1,
    this.placeStep = 0.5,
    this.placeUnknown = 0.5,
    this.strength = 0.2,
    this.strengthElse = 0.1,
    this.known = 0.1,
    this.staple = 0.15,
    this.otherGrape = 1,
    this.candidateShare = 0.5,
    this.sureShare = 0.75,
    this.tieMargin = 0.45,
  });

  /// A word the label shows that the catalog's facts of the bottle
  /// account for (its place, a grape, its producer) and its name does not,
  /// as a share of the word's weight in a name: "MONTEREY" says as much
  /// for a bottle from Monterey as for one named after it.
  final double facts;

  /// A label prints the bottle's own place, so a place the bottle lies in
  /// is worth this share of that for each step up: "CALIFORNIA" says more
  /// for a bottle the catalog places in California than for one it places
  /// in Monterey.
  final double placeStep;

  /// A bottle whose place the catalog lacks gets this share of what the
  /// best candidate got for its place, so an empty field is not a miss.
  final double placeUnknown;

  /// The label states the bottle's strength, or one a whole degree off.
  final double strength;
  final double strengthElse;

  /// A bottle people know, and a producer's everyday bottle: they come
  /// first among drinks the label says equally much for.
  final double known;
  final double staple;

  /// The label shows a grape the catalog does not give the bottle, and
  /// none it does: a Pinot Noir label is not the producer's Pinot Gris.
  final double otherGrape;

  /// The share of a name's words a label must show for the drink to be a
  /// candidate, and for it to be listed without asking.
  final double candidateShare;
  final double sureShare;

  /// A candidate this close to the likeliest is not told apart from it.
  final double tieMargin;
}

/// One thing a label says for or against a drink.
class ScoreItem {
  const ScoreItem(this.name, this.value, [this.note = '']);

  final String name;
  final double value;
  final String note;

  @override
  String toString() =>
      '$name ${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}'
      '${note.isEmpty ? '' : ' ($note)'}';
}

/// A drink a label may show, with what the label says about it. A drink's
/// years are one drink: [rows] are its catalog rows, the one to show first.
class LabelScore {
  LabelScore._(this.rows, this._name, this.items);

  final List<CatalogDrink> rows;
  final _NameShown _name;
  final List<ScoreItem> items;

  CatalogDrink get drink => rows.first;
  double get total => items.fold(0, (sum, item) => sum + item.value);

  /// The share of the name's words the label shows.
  double get share => _name.share;

  /// A word of the drink's own was read letter for letter, one that is
  /// not the name of its place: "Saint-Estèphe" is on every bottle of
  /// Saint-Estèphe and says nothing of which one this is.
  bool get exact => _name.ownExact;

  /// The label shows every word of the name.
  bool get whole => _name.whole;

  String explain() =>
      '${total.toStringAsFixed(2)} ${drink.displayName}'
      '${drink.nameEn == null ? '' : ' (${drink.nameEn})'} | ${items.join(' | ')}';
}

/// The drinks a label's searches found, likeliest first, and what to make
/// of the likeliest.
class LabelRanking {
  const LabelRanking({
    required this.scores,
    required this.matches,
    this.sure = false,
    this.tied = false,
    this.passedOver = const <String>[],
  });

  static const LabelRanking none = LabelRanking(
    scores: <LabelScore>[],
    matches: <CatalogDrink>[],
  );

  final List<LabelScore> scores;

  /// The drinks found that the label does not name, each with why, the
  /// ones it shows most of first.
  final List<String> passedOver;

  /// The catalog rows to show: every row of each drink, or one a drink
  /// when [tied], since a brand's bottles to choose from are listed once
  /// each and not once a year.
  final List<CatalogDrink> matches;

  /// The label shows most of the likeliest drink's name, a word of its
  /// own letter for letter, and no other drink as well: enough to list it
  /// without asking.
  final bool sure;

  /// The label does not tell the likeliest drink from another: one stands
  /// within [LabelWeights.tieMargin] of it, and the label shows the name
  /// of neither whole, or of both (a brand read without which bottle).
  final bool tied;
}

/// Orders the drinks the searches found ([hits], a list per search, best
/// first) by what the label says of each.
///
/// [labelLines] are the label's lines. A drink is a candidate only when
/// they show a word of its own and at least [LabelWeights.candidateShare]
/// of its name: a word or two that happen to be in a name (a keyboard's
/// "command" in Elderton Command Shiraz) name no drink, and a wrong drink
/// taken for the bottle does more harm than none. [nameTiers] are the
/// lines in the label's largest letters, then those with its next largest
/// added: a candidate must show a word of its own in the first of them
/// that names any drink, because a label prints its name large and the
/// rest small. [tagLines] are the price tag under the bottle: they weigh
/// the label's candidates ("12년" among the Windsors) and make no drink a
/// candidate. [surelyRead] are the lines sure enough to take a strength
/// from; all of them when not given.
///
/// With [trustSearch] every drink found is a candidate: a back label's
/// 제품명 field says the photo is a label and names the drink.
LabelRanking rankLabelCandidates(
  List<List<CatalogDrink>> hits, {
  required List<String> labelLines,
  List<List<String>>? nameTiers,
  List<String> tagLines = const <String>[],
  List<String>? surelyRead,
  bool trustSearch = false,
  int limit = catalogSearchPageSize,
  LabelWeights weights = const LabelWeights(),
}) {
  final label = LabelText(labelLines);
  final withTag = tagLines.isEmpty
      ? label
      : LabelText(<String>[...labelLines, ...tagLines]);
  final found = _drinksFound(hits);
  var candidates = <_Candidate>[
    for (final candidate in found)
      if (trustSearch || candidate.isNamedBy(label, weights.candidateShare))
        candidate,
  ];
  for (final tier in nameTiers ?? const <List<String>>[]) {
    final large = LabelText(tier);
    final named = candidates
        .where((candidate) => candidate.showsOwnWordIn(large))
        .toList(growable: false);
    if (named.isEmpty) continue;
    candidates = named;
    break;
  }
  final passedOver = <String>[
    for (final candidate
        in found.where((candidate) => !candidates.contains(candidate)).toList()
          ..sort(
            (a, b) => b.shownIn(label).worth.compareTo(a.shownIn(label).worth),
          ))
      candidate.whyPassedOver(label, weights.candidateShare),
  ];
  if (candidates.isEmpty) {
    return LabelRanking(
      scores: const <LabelScore>[],
      matches: const <CatalogDrink>[],
      passedOver: passedOver,
    );
  }

  final strengths = _strengthsStated(surelyRead ?? labelLines);
  final facts = <_Candidate, List<ScoreItem>>{
    for (final candidate in candidates)
      candidate: candidate.factsShown(withTag, weights),
  };
  double placeOf(_Candidate candidate) => facts[candidate]!
      .where((item) => item.name == 'place')
      .fold(0, (sum, item) => sum + item.value);
  final bestPlace = candidates.map(placeOf).reduce((a, b) => a > b ? a : b);
  // The grapes the label shows, of those the catalog gives the drinks found.
  final grapesShown = <String>{
    for (final candidate in candidates)
      for (final grape in candidate.grapes)
        if (grape.split('_').every((word) => label.shows(word) == 1)) grape,
  };
  final scores = <LabelScore>[
    for (final candidate in candidates)
      candidate.score(
        label: label,
        withTag: withTag,
        facts: facts[candidate]!,
        bestPlace: bestPlace,
        grapesShown: grapesShown,
        strengths: strengths,
        weights: weights,
      ),
  ];
  final votes = <LabelScore, int>{
    for (final (index, score) in scores.indexed) score: candidates[index].votes,
  };
  scores.sort((a, b) {
    final byScore = b.total.compareTo(a.total);
    return byScore != 0 ? byScore : votes[b]!.compareTo(votes[a]!);
  });

  final best = scores.first;
  // A name shown whole is told apart from one shown in part, however
  // close their scores.
  final tied = scores
      .skip(1)
      .any(
        (other) =>
            (other.whole || !best.whole) &&
            other.total > best.total - weights.tieMargin,
      );
  return LabelRanking(
    scores: scores,
    matches: <CatalogDrink>[
      for (final score in scores) ...tied ? score.rows.take(1) : score.rows,
    ].take(limit).toList(growable: false),
    sure: best.share >= weights.sureShare && best.exact && !tied,
    tied: tied,
    passedOver: passedOver,
  );
}

/// The drinks among [hits], a drink's years together, each with how many
/// searches found it and how high.
List<_Candidate> _drinksFound(List<List<CatalogDrink>> hits) {
  final votes = <String, int>{};
  final rows = <String, CatalogDrink>{};
  for (final list in hits) {
    for (final (rank, row) in list.indexed) {
      votes[row.id] = (votes[row.id] ?? 0) + (catalogSearchPageSize - rank);
      rows.putIfAbsent(row.id, () => row);
    }
  }
  final byDrink = <String, List<CatalogDrink>>{};
  for (final row in rows.values) {
    byDrink
        .putIfAbsent(withoutVintage(row.displayName), () => <CatalogDrink>[])
        .add(row);
  }
  return <_Candidate>[
    for (final years in byDrink.values)
      _Candidate(
        years..sort((a, b) => votes[b.id]!.compareTo(votes[a.id]!)),
        years.map((row) => votes[row.id]!).reduce((a, b) => a > b ? a : b),
      ),
  ];
}

/// What a label shows of one name.
class _NameShown {
  /// What the words read say for the drink: each by its weight, a rare
  /// word more than one many names hold.
  double seen = 0;

  /// How many of the name's words were read, of how many. A label shows
  /// a kind word as readily as any other, and a grape left unread is one
  /// word however many spell it: a label that hides "Cabernet Sauvignon"
  /// hides as much as one that hides "Merlot".
  double read = 0;
  int words = 0;
  bool ownShown = false;
  bool ownExact = false;
  bool ownMissed = false;
  bool whole = true;
  final List<String> shown = <String>[];
  final List<String> missed = <String>[];

  /// The share of the name the label shows.
  double get share => words == 0 ? 0 : read / words;

  /// Every word of the drink's own was read: all of its name but the
  /// grape and the kind, which a label can hide behind a shelf bar.
  bool get brand => ownShown && !ownMissed;

  /// What the reading says for the name: a name half shown is worth half
  /// of what was read of it. A longer name the label shows as much of is
  /// the likelier one only when the rest of it is on the label too.
  double get worth => seen * share;
}

_NameShown _nameShown(
  String name,
  LabelText text, [
  Set<String> placeWords = const <String>{},
]) {
  final result = _NameShown();
  // The words of the grape being read, and how many of them were found.
  var grapeWords = 0;
  var grapeRead = 0.0;
  void endGrape() {
    if (grapeWords == 0) return;
    result
      ..words += grapeRead == 0 ? 1 : grapeWords
      ..read += grapeRead;
    grapeWords = 0;
    grapeRead = 0;
  }

  final met = <String>{};
  for (final word in labelWords(name)) {
    // The year is the bottling, not the name: the shop's bottle is rarely
    // the year the catalog has, and is the same drink.
    if (!met.add(word) || isVintageWord(word)) continue;
    if (isTooShortToRead(word)) {
      // A read cannot tell "M" or "XR" from a scrap: a word of the name
      // that short counts as not shown, and any other is no part of it.
      if (!isNameWord(word)) continue;
      endGrape();
      result
        ..words += 1
        ..whole = false
        ..missed.add(word);
      continue;
    }
    final found = text.shows(word);
    result.seen += found * labelWordWeight(word);
    if (isGrapeWord(word)) {
      grapeWords += 1;
      grapeRead += found;
    } else {
      endGrape();
      result
        ..words += 1
        ..read += found;
    }
    if (found == 0) {
      result
        ..whole = false
        ..missed.add(word);
      if (isOwnWord(word)) result.ownMissed = true;
      continue;
    }
    result.shown.add(word);
    if (isOwnWord(word)) {
      result.ownShown = true;
      if (found == 1 && !placeWords.contains(word)) result.ownExact = true;
    }
  }
  endGrape();
  return result;
}

final RegExp _yearInName = RegExp(r'(?:19|20)\d\d(?!\d)');

final RegExp _strengthStated = RegExp(r'(\d{1,2}(?:[.,]\d{1,2})?)\s*%');

/// The strengths a label states ("ALC. 13.5% VOL"), in percent.
List<double> _strengthsStated(List<String> lines) => <double>[
  for (final line in lines)
    for (final match in _strengthStated.allMatches(line))
      ?double.tryParse(match[1]!.replaceAll(',', '.')),
].where((percent) => percent >= 2 && percent <= 75).toList(growable: false);

class _Candidate {
  _Candidate(this.rows, this.votes);

  /// The drink's catalog rows, the one most searches found first.
  final List<CatalogDrink> rows;
  final int votes;

  /// The words of the drink's catalog names. Its other names are left
  /// out: "真澄 銀撰" holds its producer's 真澄, which the label shows for
  /// every bottle of the producer and counts as the producer.
  late final Set<String> _nameWords = <String>{
    for (final row in rows) ...labelWords(row.displayName),
    for (final row in rows) ...labelWords(row.nameEn ?? ''),
  };

  /// The names the bottle goes by besides its catalog names ('真澄 銀撰').
  late final List<String> _otherNames = <String>{
    for (final facts in _facts) ...facts.names,
  }.toList(growable: false);

  Iterable<DrinkLabelFacts> get _facts =>
      rows.map((row) => row.labelFacts).nonNulls;

  /// The grape keys the catalog gives the drink.
  late final Set<String> grapes = <String>{
    for (final facts in _facts) ...facts.grapes,
  };

  /// The words of the places the drink lies in.
  late final Set<String> _placeWords = <String>{
    for (final facts in _facts)
      for (final place in facts.regions)
        for (final name in place) ...labelWords(name),
  };

  /// How much of the drink's name [text] shows, in Korean, in English or
  /// as another name it goes by: a label carries either, an import label
  /// both, and a sake label its own script.
  List<_NameShown> _shownIn(LabelText text) => <_NameShown>[
    _nameShown(rows.first.displayName, text, _placeWords),
    _nameShown(rows.first.nameEn ?? '', text, _placeWords),
    for (final name in _otherNames) _nameShown(name, text, _placeWords),
  ];

  /// The name [text] says more for.
  _NameShown shownIn(LabelText text) =>
      _shownIn(text).reduce((a, b) => b.worth > a.worth ? b : a);

  bool showsOwnWordIn(LabelText text) =>
      _shownIn(text).any((shown) => shown.ownShown);

  /// "Cabernet Sauvignon" alone is on a thousand bottles: a label names a
  /// drink only when it shows a word of the drink's own, and either
  /// [share] of one of its names or every word of its own (the brand,
  /// with the grape unread).
  bool isNamedBy(LabelText label, double share) => _shownIn(
    label,
  ).any((shown) => shown.ownShown && (shown.share >= share || shown.brand));

  String whyPassedOver(LabelText label, double share) {
    final shown = shownIn(label);
    final why = !isNamedBy(label, share)
        ? shown.ownShown
              ? 'under ${(share * 100).round()}% of the name'
              : 'no word of its own'
        : 'none of its own words in the large letters';
    return '${rows.first.displayName}: ${shown.shown.join(' ')}'
        ' ${(shown.share * 100).round()}%, $why';
  }

  /// The words [text] shows that the catalog's facts of the drink account
  /// for and its name does not, an item for each fact: the places it lies
  /// in, its grapes, its producer. A word counts once.
  List<ScoreItem> factsShown(LabelText text, LabelWeights weights) {
    final counted = <String>{..._nameWords};
    ScoreItem? item(
      String name,
      Iterable<String> words,
      String note, [
      double share = 1,
    ]) {
      final added = words.where(counted.add).toList(growable: false);
      if (added.isEmpty) return null;
      return ScoreItem(
        name,
        weights.facts *
            share *
            added.fold(0, (sum, word) => sum + labelWordWeight(word)),
        note,
      );
    }

    return <ScoreItem>[
      for (final facts in _facts)
        ...<ScoreItem?>[
          for (final (steps, place) in facts.regions.indexed)
            for (final name in place.where((name) => _showsPlace(text, name)))
              item(
                'place',
                _wordsOfPlace(name),
                name,
                math.pow(weights.placeStep, steps).toDouble(),
              ),
          for (final grape in facts.grapes)
            if (grape.split('_').every((word) => text.shows(word) == 1))
              item('grape', grape.split('_'), grape),
          for (final name in facts.producer)
            if (_ownWords(name).isNotEmpty &&
                _ownWords(name).every((word) => text.shows(word) > 0))
              item('producer', _ownWords(name), name),
        ].nonNulls,
    ];
  }

  LabelScore score({
    required LabelText label,
    required LabelText withTag,
    required List<ScoreItem> facts,
    required double bestPlace,
    required Set<String> grapesShown,
    required List<double> strengths,
    required LabelWeights weights,
  }) {
    final otherGrapes = grapesShown.difference(grapes);
    final grapeMissed =
        grapes.isNotEmpty &&
        otherGrapes.isNotEmpty &&
        grapes.intersection(grapesShown).isEmpty;
    final name = shownIn(withTag);
    return LabelScore._(_rowsFor(withTag), shownIn(label), <ScoreItem>[
      ScoreItem('name', name.seen, name.shown.join(' ')),
      if (name.missed.isNotEmpty)
        ScoreItem('unseen', name.worth - name.seen, name.missed.join(' ')),
      ...facts,
      if (bestPlace > 0 && _facts.every((facts) => facts.regions.isEmpty))
        ScoreItem('place', weights.placeUnknown * bestPlace, 'not on record'),
      if (grapeMissed)
        ScoreItem('grape', -weights.otherGrape, otherGrapes.join(' ')),
      ?_strength(strengths, weights),
      if (_facts.any((facts) => facts.known)) ScoreItem('known', weights.known),
      if (_facts.any((facts) => facts.staple))
        ScoreItem('staple', weights.staple),
    ]);
  }

  /// The drink's rows with the year the label shows first.
  List<CatalogDrink> _rowsFor(LabelText text) {
    bool yearShown(CatalogDrink row) {
      final year =
          row.labelFacts?.vintageYear?.toString() ??
          _yearInName.firstMatch(row.displayName)?[0];
      return year != null && text.shows(year) == 1;
    }

    final shown = rows.where(yearShown).take(1).toList();
    return shown.isEmpty
        ? rows
        : <CatalogDrink>[...shown, ...rows.where((row) => row != shown.single)];
  }

  ScoreItem? _strength(List<double> stated, LabelWeights weights) {
    final known = rows.map((row) => row.abvPercent).nonNulls.toList();
    if (stated.isEmpty || known.isEmpty) return null;
    final nearest = <double>[
      for (final label in stated)
        for (final abv in known) (label - abv).abs(),
    ].reduce((a, b) => a < b ? a : b);
    if (nearest < 0.05) return ScoreItem('strength', weights.strength);
    return nearest >= 1 ? ScoreItem('strength', -weights.strengthElse) : null;
  }
}

/// The words of a producer's name that are its own.
List<String> _ownWords(String name) => labelWords(
  name,
).where((word) => !isTooShortToRead(word) && isOwnWord(word)).toList();

/// The words that stand for the place [name]: the ones not many places
/// share ("colchagua" of Colchagua Valley, which a label may print as
/// "Valle de Colchagua"), or all of them when it has no such word.
List<String> _wordsOfPlace(String name) {
  final words = labelWords(
    name,
  ).where((word) => !isTooShortToRead(word)).toList(growable: false);
  final own = words.where((word) => !isPlaceKindWord(word)).toList();
  return own.isEmpty ? words : own;
}

/// Whether [text] shows every word that stands for the place [name].
bool _showsPlace(LabelText text, String name) {
  final words = _wordsOfPlace(name);
  return words.isNotEmpty && words.every((word) => text.shows(word) > 0);
}
