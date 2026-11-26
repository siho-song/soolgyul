import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import 'label_catalog_search.dart';
import 'label_layout.dart';
import 'label_match.dart';
import 'label_queries.dart';
import 'label_text_recognizer.dart';

/// What a label photo read: the photo whole, or each drink it shows by
/// itself when the detector found several, in the order they were searched.
class LabelPhotoRead {
  const LabelPhotoRead({
    this.lines = const <ReadLine>[],
    this.bottles = const <List<ReadLine>>[],
    this.bottlePhoto,
  });

  final List<ReadLine> lines;
  final List<List<ReadLine>> bottles;

  /// The photo's one bottle as the server's judge is shown it, while it is
  /// being made; it completes with `null` when the phone could not make
  /// it. `null` when the photo shows several drinks or the catalog has no
  /// judge.
  final Future<Uint8List?>? bottlePhoto;
}

/// The drinks a label photo shows, the lines searched for them, and whether
/// it was a back label.
typedef LabelPhotoFound = ({
  List<LabelFind> finds,
  List<String> queries,
  bool backSide,
});

/// One cut-out's drink, if it found one, and the lines it searched.
typedef _BottleFound = ({LabelFind? find, List<String> queries});

/// Finds the drinks a label photo shows: finds its bottles, reads each on
/// the phone, searches the catalog for what was read and ranks the drinks
/// found. A photo of one bottle is then put to the catalog's judge
/// ([LabelPhotoJudge]), which names the drink it is sure of or none; when
/// the judge gives no answer the label match's own candidates stand.
class LabelPhotoFinder {
  const LabelPhotoFinder(this._gateway, {required this.listsSeveral});

  final CatalogSearchGateway _gateway;

  /// Whether a photo of several drinks (a shelf, a menu) answers with all
  /// of them, or only with the bottle it was taken of.
  final bool listsSeveral;

  /// Reads the photo at [path] and finds its drinks. A drink cut out is
  /// searched as soon as it is read, while the next is read; of a crowded
  /// photo only the [mostBottlesRead] largest are read. A caller that
  /// wants one bottle gets only the one nearest the middle that shows any
  /// text. A photo of fewer than two drinks, or none readable, is read
  /// whole. What was read is handed to [onRead] before it is searched, as
  /// long as [current] says the search still stands, so a failed search
  /// can be repeated with [find].
  Future<LabelPhotoFound> readAndFind(
    LabelTextRecognizer recognizer,
    String path, {
    required bool Function() current,
    required void Function(LabelPhotoRead read) onRead,
  }) async {
    final LabelBottleReader? reader = switch (recognizer) {
      final LabelBottleReader reader => reader,
      _ => null,
    };
    if (reader != null) {
      var boxes = const <BottleBox>[];
      try {
        boxes = await reader.findBottles(path);
      } on LabelTextRecognitionException {
        // The photo is read whole, as on a phone without the detector.
      }
      final reads = <List<ReadLine>>[];
      final readBoxes = <BottleBox>[];
      final searches = <Future<_BottleFound?>>[];
      for (final box
          in listsSeveral
              ? readingOrder(largestBottles(boxes, mostBottlesRead))
              : nearestMiddle(boxes)) {
        if (!current()) break;
        List<ReadLine> lines;
        try {
          lines = await reader.readBottle(path, box);
        } on LabelTextRecognitionException {
          continue;
        }
        if (lines.isEmpty) continue;
        reads.add(lines);
        readBoxes.add(box);
        // Awaited below, after the next bottles are read.
        searches.add(_searchBottle(lines)..ignore());
        if (!listsSeveral) break;
      }
      if (reads.isNotEmpty) {
        final read = LabelPhotoRead(
          bottles: reads,
          bottlePhoto: reads.length == 1
              ? _bottlePhoto(reader, path, readBoxes.single)
              : null,
        );
        if (current()) onRead(read);
        return _judged(_bottlesFound(await Future.wait(searches)), read);
      }
    }
    final read = LabelPhotoRead(
      lines: await recognizer.recognizeLines(path),
      bottlePhoto: reader == null ? null : _bottlePhoto(reader, path),
    );
    if (current()) onRead(read);
    return find(read);
  }

  /// Finds the drinks of a label already read.
  Future<LabelPhotoFound> find(LabelPhotoRead read) async {
    if (read.bottles.isNotEmpty) {
      return _judged(
        _bottlesFound(
          await Future.wait(<Future<_BottleFound?>>[
            for (final lines in read.bottles) _searchBottle(lines),
          ]),
        ),
        read,
      );
    }
    final photo = await searchCatalogByPhoto(_gateway, read.lines);
    // A photo of several read whole keeps one find a label.
    if (listsSeveral && photo.listed.length > 1) {
      return (
        finds: photo.listed,
        queries: photo.queries,
        backSide: photo.backSide,
      );
    }
    return _judged((
      finds: <LabelFind>[?await _matchedMain(read.lines, photo)],
      queries: photo.queries,
      backSide: photo.backSide,
    ), read);
  }

  /// The one bottle of the photo at [path] for the judge; `null` without a
  /// judge to show it to.
  Future<Uint8List?>? _bottlePhoto(
    LabelBottleReader reader,
    String path, [
    BottleBox? bottle,
  ]) {
    if (_gateway is! LabelPhotoJudge) return null;
    return () async {
      try {
        return await reader.bottlePhoto(path, bottle);
      } on LabelTextRecognitionException {
        return null;
      }
    }();
  }

  /// [found] as the judge leaves it when it is one bottle's candidates and
  /// [read] has that bottle's photo: the one drink the judge names, sure,
  /// or no drink at all. Anything else, and a judge that gives no answer,
  /// leave [found] as it is.
  Future<LabelPhotoFound> _judged(
    LabelPhotoFound found,
    LabelPhotoRead read,
  ) async {
    final LabelPhotoJudge? judge = switch (_gateway) {
      final LabelPhotoJudge judge => judge,
      _ => null,
    };
    final find = found.finds.singleOrNull;
    if (judge == null || find == null) return found;
    final photo = await read.bottlePhoto;
    if (photo == null) return found;
    final String? drinkId;
    try {
      drinkId = await judge.pickByPhoto(photo, <String>[
        for (final drink in find.search.matches) drink.id,
      ], appSure: find.search.sure);
    } on LabelPhotoJudgeException {
      return found;
    }
    final drink = find.search.matches
        .where((drink) => drink.id == drinkId)
        .firstOrNull;
    return (
      finds: <LabelFind>[
        if (drink != null)
          LabelFind(
            group: find.group,
            search: LabelSearch(
              queries: find.search.queries,
              matches: <CatalogDrink>[drink],
              sure: true,
            ),
          ),
      ],
      queries: found.queries,
      backSide: found.backSide,
    );
  }

  /// The bottle the photo was taken of, its drinks as the label match ranks
  /// them ([matchLabelPhoto]); the line search's own answer when the
  /// catalog has no word search, it fails, or it finds nothing.
  Future<LabelFind?> _matchedMain(
    List<ReadLine> lines,
    PhotoSearch photo,
  ) async {
    final main = photo.main;
    if (_gateway case final LabelWordSearch words) {
      final LabelMatch match;
      try {
        match = await matchLabelPhoto(words, lines, lineSearch: photo);
      } on CatalogSearchException {
        return main;
      }
      if (match.drinks.isNotEmpty) {
        return _matched(
          match,
          main?.group ?? LabelGroup(lines: lines),
          main?.search.queries ?? photo.queries,
        );
      }
    }
    return main;
  }

  /// The drinks of the photo's cut-outs, from each one's search. One drink
  /// found twice shows once. Fails only when every search failed.
  LabelPhotoFound _bottlesFound(List<_BottleFound?> searched) {
    if (searched.every((result) => result == null)) {
      throw const CatalogSearchException();
    }
    final shown = <String>{};
    return (
      finds: <LabelFind>[
        for (final result in searched)
          if (result?.find case final find? when shown.add(find.drink.id)) find,
      ],
      queries: <String>[for (final result in searched) ...?result?.queries],
      backSide: false,
    );
  }

  /// One cut-out's drinks, ranked by the label match from its words alone;
  /// `null` when its search failed. A catalog without the word search
  /// line-searches it instead.
  Future<_BottleFound?> _searchBottle(List<ReadLine> lines) async {
    try {
      final LabelWordSearch words;
      if (_gateway case final LabelWordSearch found) {
        words = found;
      } else {
        final photo = await searchCatalogByPhoto(_gateway, lines);
        return (find: photo.main, queries: photo.queries);
      }
      final match = await matchLabelPhoto(words, lines, cut: true);
      final group = LabelGroup(lines: lines);
      final queries = labelSearchQueries(<String>[
        for (final line in group.largestFirst) line.text,
      ]);
      return (
        find: match.drinks.isEmpty ? null : _matched(match, group, queries),
        queries: queries,
      );
    } on CatalogSearchException {
      return null;
    }
  }
}

/// What the label match made of the label in [group]: its twenty likeliest
/// drinks, and whether it is sure of the first or only of their brand.
LabelFind _matched(LabelMatch match, LabelGroup group, List<String> queries) {
  return LabelFind(
    group: group,
    search: LabelSearch(
      queries: queries,
      matches: match.drinks.take(20).toList(growable: false),
      sure: match.state == LabelMatchState.sure,
      tied: match.state == LabelMatchState.brand,
    ),
  );
}

/// [bottles] row by row from the top, each row left to right. A bottle
/// starts a new row when its middle is below the bottom of every bottle in
/// the row so far.
@visibleForTesting
List<BottleBox> readingOrder(List<BottleBox> bottles) {
  final down = [...bottles]
    ..sort((a, b) => (a.top + a.bottom).compareTo(b.top + b.bottom));
  final rows = <List<BottleBox>>[];
  for (final bottle in down) {
    final middle = (bottle.top + bottle.bottom) / 2;
    if (rows.isNotEmpty && rows.last.any((other) => middle < other.bottom)) {
      rows.last.add(bottle);
    } else {
      rows.add(<BottleBox>[bottle]);
    }
  }
  return <BottleBox>[
    for (final row in rows) ...(row..sort((a, b) => a.left.compareTo(b.left))),
  ];
}

/// The most bottles of one photo that are read. Reading is what a shelf
/// photo waits for, about a third of a second a bottle, and the small
/// bottles of a crowded shelf are the ones that read wrong.
const mostBottlesRead = 10;

/// The [count] bottles of [bottles] that take up most of the photo.
@visibleForTesting
List<BottleBox> largestBottles(List<BottleBox> bottles, int count) {
  if (bottles.length <= count) return bottles;
  double area(BottleBox bottle) =>
      (bottle.right - bottle.left) * (bottle.bottom - bottle.top);
  return ([
    ...bottles,
  ]..sort((a, b) => area(b).compareTo(area(a)))).sublist(0, count);
}

/// [bottles], the one whose middle is nearest the photo's first.
@visibleForTesting
List<BottleBox> nearestMiddle(List<BottleBox> bottles) {
  double away(BottleBox bottle) {
    final x = (bottle.left + bottle.right) / 2 - 0.5;
    final y = (bottle.top + bottle.bottom) / 2 - 0.5;
    return x * x + y * y;
  }

  return [...bottles]..sort((a, b) => away(a).compareTo(away(b)));
}
