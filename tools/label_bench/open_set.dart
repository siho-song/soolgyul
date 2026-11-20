// The open set: photos of wine and whisky that Open Food Facts users posted
// (images CC BY-SA, data ODbL; each photo keeps its barcode), and of sake
// and Korean liquor from Wikimedia Commons (free licences; each photo keeps
// its file title), read on a Mac
// with the app's Vision settings at the app camera's size (`1280`) and at
// the size posted (`full`). Each bottle a person can name in a photo is
// answered: a catalog drink (`same`), another bottle of a producer the
// catalog has (`sibling`), or a drink the catalog lacks (`absent`). Photos
// are graded by quality (`상` every condition good, `하` at least one bad:
// back label, glare or a hidden name, a small or heavily blurred name).
//
// About 30% of the photos are check photos (`split`), kept apart by kind
// and answer, with every photo of one catalog drink on one side. Rules are
// worked out on the tune photos only; the check photos are scored but never
// opened one by one, so their scores say how a rule does on photos it was
// not made for. The shop photos (`shop`) are shelves and counters in shops,
// screenshots no larger than the app camera's size, so read once; they are
// checked only, like the check photos.
//
// Each group is scored the way a search that may meet an unknown bottle is:
// for photos of a catalog drink, how often it comes first, is among the
// candidates, is shown as sure, and how often another drink is; for photos
// of a drink the catalog lacks, how often a drink is shown as sure anyway;
// and of all the drinks shown as sure, how many the photo holds.
//
//   dart run tools/label_bench/open_set.dart
//       the scores by size, side and kind
//   dart run tools/label_bench/open_set.dart --photos wine/
//       each tune photo of a kind (or one photo id) as it came out
//   SB_URL=… SB_KEY=… dart run tools/label_bench/open_set.dart --record
//       asks the catalog for searches the recording lacks
//   … --answers <file under data/>
//       replays (or records into) another recording, such as one of a
//       changed catalog
import 'dart:convert';
import 'dart:io';

import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_catalog_search.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_layout.dart';

import 'label_bench.dart';

/// One bottle a person can name in a photo.
class OpenBottle {
  const OpenBottle(this.answer, this.names);

  /// `same`, `sibling` or `absent`.
  final String answer;

  /// For `same`, the catalog drinks without their years it may be shown
  /// as: one, or several when the photo cannot tell them apart (a batch
  /// number it hides, a line too small to read) or the catalog holds the
  /// drink twice.
  final List<String> names;

  String? get name => names.isEmpty ? null : names.first;
}

/// One photo of the open set as one size of it read.
class OpenPhoto {
  const OpenPhoto({
    required this.id,
    required this.kind,
    required this.grade,
    required this.split,
    required this.size,
    required this.lines,
    required this.bottles,
  });

  final String id;

  /// `wine`, `whisky`, `sake` or `korean_traditional`.
  final String kind;

  /// `상`, `중` or `하`.
  final String grade;

  /// `tune`, `check` or `shop` (shop shelves, checked only).
  final String split;

  /// `1280` or `full`.
  final String size;
  final List<ReadLine> lines;

  /// The registered bottle first.
  final List<OpenBottle> bottles;

  OpenBottle get registered => bottles.first;

  /// The bottles the catalog has.
  Iterable<OpenBottle> get known =>
      bottles.where((bottle) => bottle.answer == 'same');

  Set<String> get drinks => <String>{
    for (final bottle in known) ...bottle.names,
  };
}

List<OpenPhoto> loadOpenPhotos() {
  final saved =
      jsonDecode(
            utf8.decode(
              gzip.decode(
                File('tools/label_bench/data/open.json.gz').readAsBytesSync(),
              ),
            ),
          )
          as Map<String, dynamic>;
  return <OpenPhoto>[
    for (final MapEntry(key: id, value: photo as Map<String, dynamic>)
        in saved.entries)
      for (final MapEntry(key: size, value: reads)
          in (photo['reads'] as Map<String, dynamic>).entries)
        OpenPhoto(
          id: id,
          kind: photo['kind'] as String,
          grade: photo['grade'] as String,
          split: photo['split'] as String,
          size: size,
          lines: benchLines(reads),
          bottles: <OpenBottle>[
            for (final bottle in photo['bottles'] as List)
              OpenBottle((bottle as List)[0] as String, <String>[
                for (final name in bottle.skip(1)) benchName(name as String),
              ]),
          ],
        ),
  ];
}

/// How the registered bottle came out.
enum OpenOutcome {
  /// A catalog drink shown first in a row.
  top,

  /// Among the candidates of a row shown, not first.
  candidate,

  /// Rows shown and none is it.
  wrong,

  /// Nothing shown.
  none,

  /// Not in the catalog, and nothing shown as sure.
  quiet,

  /// Not in the catalog, and another drink shown as sure.
  claimed,

  /// The search failed.
  failed,
}

class OpenResult {
  const OpenResult(this.photo, this.found);

  final OpenPhoto photo;
  final PhotoSearch? found;

  List<LabelFind> get listed => found?.listed ?? const <LabelFind>[];

  bool _shows(OpenBottle bottle) => listed.any(
    (find) => bottle.names.contains(benchName(find.drink.displayName)),
  );

  bool _offers(OpenBottle bottle) => listed.any(
    (find) => find.search.matches
        .take(5)
        .any((drink) => bottle.names.contains(benchName(drink.displayName))),
  );

  OpenOutcome get outcome {
    if (found == null) return OpenOutcome.failed;
    final registered = photo.registered;
    if (registered.answer != 'same') {
      return sureAndWrong > 0 ? OpenOutcome.claimed : OpenOutcome.quiet;
    }
    if (_shows(registered)) return OpenOutcome.top;
    if (listed.isEmpty) return OpenOutcome.none;
    return _offers(registered) ? OpenOutcome.candidate : OpenOutcome.wrong;
  }

  /// Drinks shown as sure that the photo does not hold.
  int get sureAndWrong => listed
      .where(
        (find) =>
            find.search.sure &&
            !photo.drinks.contains(benchName(find.drink.displayName)),
      )
      .length;

  /// Drinks shown as sure.
  int get sureShown => listed.where((find) => find.search.sure).length;

  /// The registered bottle, a catalog drink, shown as sure.
  bool get registeredSure =>
      photo.registered.answer == 'same' &&
      listed.any(
        (find) =>
            find.search.sure &&
            photo.registered.names.contains(benchName(find.drink.displayName)),
      );

  /// The bottles of the photo the catalog has shown first in a row.
  int get drinksShown => photo.known.where(_shows).length;
}

Future<List<OpenResult>> runOpenSet(
  CatalogSearchGateway catalog,
  List<OpenPhoto> photos, {
  void Function(int done)? progress,
}) async {
  final results = <OpenResult>[];
  for (final photo in photos) {
    PhotoSearch? found;
    try {
      found = await searchCatalogByPhoto(catalog, photo.lines);
    } on CatalogSearchException {
      found = null;
    }
    results.add(OpenResult(photo, found));
    progress?.call(results.length);
  }
  return results;
}

/// The scores of one group of photos.
class OpenScore {
  OpenScore(this.name, List<OpenResult> results) {
    for (final result in results) {
      if (result.photo.registered.answer == 'same') {
        known += 1;
        if (result.outcome == OpenOutcome.top) top += 1;
        if (result.outcome == OpenOutcome.candidate) candidate += 1;
        if (result.registeredSure) sureRight += 1;
        if (result.sureAndWrong > 0) knownClaimed += 1;
      } else {
        unknown += 1;
        if (result.sureAndWrong > 0) unknownClaimed += 1;
      }
      if (result.found == null) failed += 1;
      sureShown += result.sureShown;
      sureWrong += result.sureAndWrong;
    }
  }

  final String name;

  /// Photos of a catalog drink: shown first, among the candidates, shown
  /// as sure, and with another drink shown as sure.
  int known = 0, top = 0, candidate = 0, sureRight = 0, knownClaimed = 0;

  /// Photos of a drink the catalog lacks, and those with a drink shown as
  /// sure anyway.
  int unknown = 0, unknownClaimed = 0;

  /// Drinks shown as sure, and those the photo does not hold.
  int sureShown = 0, sureWrong = 0;

  int failed = 0;

  static String _pct(int n, int of) =>
      (of == 0 ? '-' : '${(100 * n / of).round()}%').padLeft(4);

  @override
  String toString() =>
      '${name.padRight(6)}'
      ' 있는 술 ${'$known'.padLeft(3)}'
      ' | 첫 줄 정답 ${_pct(top, known)}'
      ' | 후보 안 ${_pct(candidate, known)}'
      ' | 확신해서 맞힘 ${_pct(sureRight, known)}'
      ' | 다른 술로 확신 ${_pct(knownClaimed, known)}'
      ' || 없는 술 ${'$unknown'.padLeft(3)}'
      ' | 잘못 받아들임 ${_pct(unknownClaimed, unknown)}'
      ' || 확신 정밀도 ${_pct(sureShown - sureWrong, sureShown)}'
      ' (${sureShown - sureWrong}/$sureShown)'
      '${failed == 0 ? '' : ' | 실패 $failed'}';
}

const Map<String, String> _kindNames = <String, String>{
  'wine': '와인',
  'whisky': '위스키',
  'sake': '사케',
  'korean_traditional': '전통주',
};

const Map<String, String> _splitNames = <String, String>{
  'tune': '맞추기용',
  'check': '확인용',
  'shop': '매장 사진',
};

/// The scores of one size and side, by kind, then of all kinds.
List<OpenScore> scoreOpenSet(List<OpenResult> results) => <OpenScore>[
  for (final MapEntry(key: kind, value: name) in _kindNames.entries)
    OpenScore(name, results.where((r) => r.photo.kind == kind).toList()),
  OpenScore('전체', results),
];

Future<void> main(List<String> args) async {
  final answers = args.indexOf('--answers');
  final catalog = RecordedCatalog(
    record: args.contains('--record'),
    file: answers >= 0 ? args[answers + 1] : 'open_answers.json.gz',
  );
  var photos = loadOpenPhotos();
  final only = args.indexOf('--photos');
  if (only >= 0) {
    final wanted = args[only + 1];
    photos = photos
        .where(
          (p) =>
              p.split == 'tune' &&
              '${p.kind}/${p.id}/${p.size}'.contains(wanted),
        )
        .toList();
  }
  final results = await runOpenSet(
    catalog,
    photos,
    progress: catalog.record
        ? (done) {
            if (done % 100 == 0) {
              catalog.save();
              stderr.writeln('$done/${photos.length}, calls ${catalog.asked}');
            }
          }
        : null,
  );
  if (catalog.record) catalog.save();
  final dump = args.indexOf('--dump');
  if (dump >= 0) {
    File(args[dump + 1]).writeAsStringSync(
      results
          .map(
            (r) => jsonEncode(<String, Object?>{
              'id': r.photo.id,
              'size': r.photo.size,
              'outcome': r.outcome.name,
              'queries': r.found?.queries,
              'listed': <Object?>[
                for (final find in r.listed)
                  <String, Object?>{
                    'sure': find.search.sure,
                    'tied': find.search.tied,
                    'lines': find.group.lines.map((l) => l.text).toList(),
                    'matches': find.search.matches
                        .take(5)
                        .map((d) => d.displayName)
                        .toList(),
                    'explained': find.search.explained,
                  },
              ],
              // Found and not shown: neither the main drink nor sure.
              'unlisted': <Object?>[
                for (final find in r.found?.finds ?? const <LabelFind>[])
                  if (!r.listed.contains(find))
                    <String, Object?>{
                      'lines': find.group.lines.map((l) => l.text).toList(),
                      'matches': find.search.matches
                          .take(5)
                          .map((d) => d.displayName)
                          .toList(),
                    },
              ],
              'groups':
                  (r.found?.finds.length ?? 0) + (r.found?.unnamed.length ?? 0),
            }),
          )
          .join('\n'),
    );
  }
  if (only >= 0) {
    for (final result in results) {
      final photo = result.photo;
      stdout.writeln(
        '${photo.kind}/${photo.id}/${photo.size} ${photo.grade}'
        ' ${result.outcome.name}  정답: ${photo.bottles.map((b) => b.name ?? b.answer).join(', ')}'
        '  보임: ${result.listed.map((find) => '${find.drink.displayName}${find.search.sure
            ? '!'
            : find.search.tied
            ? '?'
            : ''}').join(' | ')}',
      );
    }
    return;
  }
  for (final size in <String>['1280', 'full']) {
    for (final MapEntry(key: split, value: splitName) in _splitNames.entries) {
      final side = results
          .where((r) => r.photo.size == size && r.photo.split == split)
          .toList();
      if (side.isEmpty) continue;
      stdout.writeln('\n── $size · $splitName ${side.length}장 ──');
      scoreOpenSet(side).forEach(stdout.writeln);
      final multi = side.where(
        (r) => r.photo.bottles.length > 1 && r.photo.known.isNotEmpty,
      );
      final drinks = multi.fold(0, (sum, r) => sum + r.photo.known.length);
      final shown = multi.fold(0, (sum, r) => sum + r.drinksShown);
      stdout.writeln('여러 병 사진 ${multi.length}장: 목록에 있는 술 $shown/$drinks 보임');
    }
  }
}
