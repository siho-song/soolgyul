import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../catalog/data/catalog_drink.dart';
import '../../catalog/data/catalog_search_gateway.dart';
import 'label_catalog_search.dart';
import 'label_layout.dart';
import 'label_match.dart';
import 'label_queries.dart';
import 'label_text_recognizer.dart';

/// What a label photo read: the photo whole, or the one bottle it was
/// taken of, cut out, when the detector found several.
class LabelPhotoRead {
  const LabelPhotoRead({
    this.lines = const <ReadLine>[],
    this.cut = false,
    this.bottlePhoto,
  });

  final List<ReadLine> lines;

  /// Whether [lines] are of one bottle cut out of the photo.
  final bool cut;

  /// The bottle as the server's judge is shown it, while it is being made;
  /// it completes with `null` when the phone could not make it. `null`
  /// when the catalog has no judge.
  final Future<Uint8List?>? bottlePhoto;
}

/// The drink a label photo shows (at most one find), the lines searched
/// for it, and whether it was a back label.
typedef LabelPhotoFound = ({
  List<LabelFind> finds,
  List<String> queries,
  bool backSide,
});

/// Finds the drink a label photo shows: reads the photo's one bottle on
/// the phone, searches the catalog for what was read and ranks the drinks
/// found. The bottle is then put to the catalog's judge
/// ([LabelPhotoJudge]), which names the drink it is sure of or none; when
/// the judge gives no answer the label match's own candidates stand.
class LabelPhotoFinder {
  const LabelPhotoFinder(this._gateway, {this.judgesAsFound = true});

  final CatalogSearchGateway _gateway;

  /// Whether the bottle's candidates go to the judge as soon as they are
  /// found. A caller that reads photos before it is asked for their drinks
  /// says no, and has them judged ([judged]) when it is: the bottle's photo
  /// leaves the phone only then.
  final bool judgesAsFound;

  /// Reads the photo at [path] and finds its drink. Of a photo of several
  /// bottles only one is read, cut out: the one nearest the middle that
  /// shows any text. A photo of fewer than two, or none readable, is read
  /// whole. What was read is handed to [onRead] before it is searched, as
  /// long as [current] says the search still stands, so a failed search
  /// can be repeated with [find].
  ///
  /// A caller that has found the photo's bottles already hands them in as
  /// [bottles]. [onPhotoRead] is called once the phone has read the photo,
  /// while the search and the judge are still out, so a caller with more
  /// photos can have the next one read.
  Future<LabelPhotoFound> readAndFind(
    LabelTextRecognizer recognizer,
    String path, {
    required bool Function() current,
    required void Function(LabelPhotoRead read) onRead,
    List<BottleBox>? bottles,
    void Function()? onPhotoRead,
  }) async {
    final LabelBottleReader? reader = switch (recognizer) {
      final LabelBottleReader reader => reader,
      _ => null,
    };
    if (reader != null) {
      var boxes = bottles ?? const <BottleBox>[];
      if (bottles == null) {
        try {
          boxes = await reader.findBottles(path);
        } on LabelTextRecognitionException {
          // The photo is read whole, as on a phone without the detector.
        }
      }
      for (final box in nearestMiddle(boxes)) {
        if (!current()) break;
        final List<ReadLine> lines;
        try {
          lines = await reader.readBottle(path, box);
        } on LabelTextRecognitionException {
          continue;
        }
        if (lines.isEmpty) continue;
        final read = LabelPhotoRead(
          lines: lines,
          cut: true,
          bottlePhoto: _bottlePhoto(reader, path, box),
        );
        if (current()) onRead(read);
        onPhotoRead?.call();
        return find(read);
      }
    }
    final read = LabelPhotoRead(
      lines: await recognizer.recognizeLines(path),
      bottlePhoto: reader == null ? null : _bottlePhoto(reader, path),
    );
    onPhotoRead?.call();
    if (current()) onRead(read);
    return find(read);
  }

  /// Finds the drink of a label already read.
  Future<LabelPhotoFound> find(LabelPhotoRead read) async {
    if (read.cut) return _asFound(await _searchBottle(read.lines), read);
    // The words are asked while the line search is out.
    final ahead = switch (_gateway) {
      final LabelWordSearch words => labelWordsAhead(words, read.lines),
      _ => null,
    };
    // Not awaited when the line search fails.
    ahead?.ignore();
    final photo = await searchCatalogByPhoto(_gateway, read.lines);
    return _asFound((
      finds: <LabelFind>[?await _matchedMain(read.lines, photo, ahead)],
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

  Future<LabelPhotoFound> _asFound(LabelPhotoFound found, LabelPhotoRead read) {
    return judgesAsFound
        ? judged(found, read)
        : Future<LabelPhotoFound>.value(found);
  }

  /// [found] as the judge leaves it when it has candidates and [read] the
  /// bottle's photo: the one drink the judge names, sure, or no drink at
  /// all. Anything else, and a judge that gives no answer, leave [found]
  /// as it is.
  Future<LabelPhotoFound> judged(
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
    Future<List<LabelCandidate>>? wordsAhead,
  ) async {
    final main = photo.main;
    if (_gateway case final LabelWordSearch words) {
      final LabelMatch match;
      try {
        match = await matchLabelPhoto(
          words,
          lines,
          lineSearch: photo,
          wordsAhead: wordsAhead,
        );
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

  /// A cut-out's drinks, ranked by the label match from its words alone. A
  /// catalog without the word search line-searches it instead.
  Future<LabelPhotoFound> _searchBottle(List<ReadLine> lines) async {
    final LabelWordSearch words;
    if (_gateway case final LabelWordSearch found) {
      words = found;
    } else {
      final photo = await searchCatalogByPhoto(_gateway, lines);
      return (
        finds: <LabelFind>[?photo.main],
        queries: photo.queries,
        backSide: false,
      );
    }
    final match = await matchLabelPhoto(words, lines, cut: true);
    final group = LabelGroup(lines: lines);
    final queries = labelSearchQueries(<String>[
      for (final line in group.largestFirst) line.text,
    ]);
    return (
      finds: <LabelFind>[
        if (match.drinks.isNotEmpty) _matched(match, group, queries),
      ],
      queries: queries,
      backSide: false,
    );
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
