// Replays label photos through the app's label search and grades what it
// finds. The photos are kept as what a phone read off them (`data/`), and
// the catalog as what it answered each search when recorded, so a run
// needs no network and gives the same scores until the code changes.
//
//   dart run tools/label_bench/label_bench.dart
//       the scores
//   dart run tools/label_bench/label_bench.dart --explain shelf/006/iphone
//       one photo: what was read, each drink found and why
//   dart run tools/label_bench/label_bench.dart --weights staple=0,known=0
//       the scores with some of the weights changed, to see what a weight
//       is worth before changing it in `label_score.dart`
//   SB_URL=… SB_KEY=… dart run tools/label_bench/label_bench.dart --record
//       also asks the catalog for searches the recording lacks, and keeps
//       the answers (needed after a change to which lines are searched)
//
// `test/features/label_bench_test.dart` runs the same scores as a test
// and fails when one falls below what it holds.
import 'dart:convert';
import 'dart:io';

import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_catalog_search.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_layout.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_score.dart';

const String _data = 'tools/label_bench/data';

/// One photo as one device read it, and the drink it shows.
class BenchPhoto {
  const BenchPhoto({
    required this.set,
    required this.id,
    required this.device,
    required this.lines,
    required this.truth,
    this.inCatalog = true,
  });

  /// `shelf` (a bottle among others in a shop), `bottle` (a product photo
  /// of one bottle) or `menu` (a wine list).
  final String set;
  final String id;
  final String device;
  final List<ReadLine> lines;

  /// The drinks the photo is of, by name without the year: one for a
  /// bottle, every entry for a menu.
  final List<String> truth;

  /// The catalog has the drink; a photo of one it lacks should find none.
  final bool inCatalog;

  String get name => '$set/$id/$device';
}

/// Lines as the bench keeps them: `[text, left, top, width, height,
/// confidence]`, fractions of the photo from its top-left corner.
List<ReadLine> benchLines(Object? reads) => <ReadLine>[
  for (final read in reads as List)
    ReadLine(
      text: (read as List)[0] as String,
      left: (read[1] as num).toDouble(),
      top: (read[2] as num).toDouble(),
      width: (read[3] as num).toDouble(),
      height: (read[4] as num).toDouble(),
      confidence: (read[5] as num).toDouble(),
    ),
];

Map<String, dynamic> _json(String file) =>
    jsonDecode(File('$_data/$file').readAsStringSync()) as Map<String, dynamic>;

/// Every photo of the bench, a photo once per device that read it.
List<BenchPhoto> loadBenchPhotos() {
  final photos = <BenchPhoto>[];
  void add(String set, String id, Map<String, dynamic> photo) {
    final truth = photo['truth'];
    for (final MapEntry(key: device, value: reads)
        in (photo['reads'] as Map<String, dynamic>).entries) {
      photos.add(
        BenchPhoto(
          set: set,
          id: id,
          device: device,
          lines: benchLines(reads),
          truth: <String>[
            for (final name in truth is List ? truth : <Object?>[truth])
              (name as String).trim().replaceAll(_year, ''),
          ],
          inCatalog: photo['in_catalog'] as bool? ?? true,
        ),
      );
    }
  }

  for (final MapEntry(key: id, value: photo) in _json('shelf.json').entries) {
    add('shelf', id, photo as Map<String, dynamic>);
  }
  for (final MapEntry(key: id, value: photo) in _json('bottles.json').entries) {
    add('bottle', id, photo as Map<String, dynamic>);
  }
  add('menu', 'wine-list', _json('menu.json'));
  return photos;
}

/// The catalog as it answered when recorded: every label search by its
/// line. With [record], a line it lacks is asked of the catalog at
/// `SB_URL` and kept.
class RecordedCatalog implements CatalogSearchGateway {
  RecordedCatalog({this.record = false, this.file = 'answers.json.gz'}) {
    final file = File('$_data/${this.file}');
    if (!file.existsSync()) return;
    final saved =
        jsonDecode(utf8.decode(gzip.decode(file.readAsBytesSync())))
            as Map<String, dynamic>;
    _drinks.addAll((saved['drinks'] as List).cast<Map<String, dynamic>>());
    for (final (index, drink) in _drinks.indexed) {
      _indexOf[drink['id'] as String] = index;
    }
    for (final MapEntry(key: line, value: found)
        in (saved['answers'] as Map<String, dynamic>).entries) {
      _answers[line] = (found as List?)?.cast<int>();
    }
  }

  final bool record;

  /// The recording under `data/`.
  final String file;
  final List<Map<String, dynamic>> _drinks = <Map<String, dynamic>>[];
  final Map<String, int> _indexOf = <String, int>{};

  /// A line's drinks as indexes into [_drinks]; `null` for a line the
  /// catalog failed to answer in time.
  final Map<String, List<int>?> _answers = <String, List<int>?>{};
  final HttpClient _http = HttpClient();
  int asked = 0;

  void save() {
    final lines = _answers.keys.toList()..sort();
    File('$_data/$file').writeAsBytesSync(
      gzip.encode(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'drinks': _drinks,
            'answers': <String, Object?>{
              for (final line in lines) line: _answers[line],
            },
          }),
        ),
      ),
    );
  }

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = catalogSearchPageSize,
    int offset = 0,
  }) => throw UnimplementedError('the bench searches by label only');

  @override
  Future<List<List<CatalogDrink>>> searchMany(
    List<String> queries, {
    int limit = 10,
    bool readOffLabel = false,
  }) async {
    final missing = queries.where((line) => !_answers.containsKey(line));
    if (missing.isNotEmpty) {
      if (!record) {
        throw StateError(
          'no recorded answer for ${missing.toList()}: run with --record',
        );
      }
      await _ask(missing.toSet().toList());
    }
    if (queries.any((line) => _answers[line] == null)) {
      throw const CatalogSearchException();
    }
    return <List<CatalogDrink>>[
      for (final line in queries)
        _answers[line]!
            .take(limit)
            .map((index) => _drink(_drinks[index]))
            .toList(),
    ];
  }

  CatalogDrink _drink(Map<String, dynamic> row) => CatalogDrink(
    id: row['id'] as String,
    displayName: row['name_ko'] as String,
    nameEn: row['name_en'] as String?,
    category: DrinkCategory.other,
    abvPercent: (row['abv_percent'] as num?)?.toDouble(),
    countryCode: row['country_code'] as String?,
    labelFacts: DrinkLabelFacts.fromJson(row['label_facts']),
  );

  Future<void> _ask(List<String> lines) async {
    final base = Platform.environment['SB_URL'];
    final key = Platform.environment['SB_KEY'];
    if (base == null || key == null) {
      throw StateError('--record needs SB_URL and SB_KEY');
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      asked++;
      final request = await _http.postUrl(
        Uri.parse('$base/rest/v1/rpc/soolgyul_search_alcohol_catalog_by_label'),
      );
      request.headers
        ..set('apikey', key)
        ..set('Authorization', 'Bearer $key')
        ..set('Content-Type', 'application/json');
      request.add(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'target_queries': lines,
            'target_limit': catalogSearchPageSize,
          }),
        ),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode != 200) continue;
      final found = <List<int>>[for (final _ in lines) <int>[]];
      for (final row
          in (jsonDecode(body) as List).cast<Map<String, dynamic>>()) {
        final index = _indexOf.putIfAbsent(row['id'] as String, () {
          _drinks.add(<String, dynamic>{
            for (final field in const <String>[
              'id',
              'name_ko',
              'name_en',
              'abv_percent',
              'country_code',
              'label_facts',
            ])
              if (row[field] != null) field: row[field],
          });
          return _drinks.length - 1;
        });
        found[(row['query_index'] as int) - 1].add(index);
      }
      for (final (at, line) in lines.indexed) {
        _answers[line] = found[at];
      }
      return;
    }
    for (final line in lines) {
      _answers[line] = null;
    }
  }
}

final RegExp _year = RegExp(r'\s+(?:19|20)\d\d$');

/// A drink's name without its year: one drink's years are one drink.
String _drinkName(CatalogDrink drink) => benchName(drink.displayName);

/// A catalog name without its year.
String benchName(String name) => name.trim().replaceAll(_year, '');

/// How a photo's search came out.
enum Outcome {
  /// The drink is the first of a row the photo lists.
  top,

  /// The drink is among a listed row's candidates, not first.
  candidate,

  /// Drinks are listed and none is the one.
  wrong,

  /// Nothing is listed.
  none,

  /// The search failed.
  failed,
}

class PhotoResult {
  const PhotoResult(this.photo, this.found);

  final BenchPhoto photo;

  /// `null` when the search failed.
  final PhotoSearch? found;

  List<LabelFind> get listed => found?.listed ?? const <LabelFind>[];

  Outcome get outcome {
    if (found == null) return Outcome.failed;
    if (listed.isEmpty) return Outcome.none;
    final truth = photo.truth.single;
    if (listed.any((find) => _drinkName(find.drink) == truth)) {
      return Outcome.top;
    }
    final among = listed.any(
      (find) => find.search.matches.take(5).map(_drinkName).contains(truth),
    );
    return among ? Outcome.candidate : Outcome.wrong;
  }

  /// Rows listed without asking that are not the photo's drink. On a
  /// shelf a neighbour's bottle is such a row and no mistake, so this
  /// counts for a photo of one bottle only.
  int get sureAndWrong => listed
      .where(
        (find) =>
            find.search.sure && !photo.truth.contains(_drinkName(find.drink)),
      )
      .length;

  /// The menu entries found, each by the first drink of its row.
  int get entriesRight => photo.truth
      .where((name) => listed.any((find) => _drinkName(find.drink) == name))
      .length;
}

Future<List<PhotoResult>> runBench(
  CatalogSearchGateway catalog,
  List<BenchPhoto> photos, {
  LabelWeights weights = const LabelWeights(),
}) async {
  final results = <PhotoResult>[];
  for (final photo in photos) {
    PhotoSearch? found;
    try {
      found = await searchCatalogByPhoto(
        catalog,
        photo.lines,
        weights: weights,
      );
    } on CatalogSearchException {
      found = null;
    }
    results.add(PhotoResult(photo, found));
  }
  return results;
}

/// The counts a change is judged by, one row per set and device.
class BenchScore {
  BenchScore(this.name, List<PhotoResult> results)
    : photos = results.length,
      read = results.where((r) => r.photo.lines.isNotEmpty).length,
      outcomes = <Outcome, int>{
        for (final outcome in Outcome.values)
          outcome: results
              .where((r) => r.photo.lines.isNotEmpty && r.outcome == outcome)
              .length,
      },
      sureAndWrong = results.fold(0, (sum, r) => sum + r.sureAndWrong),
      rows = results.fold(0, (sum, r) => sum + r.listed.length);

  final String name;
  final int photos;

  /// Photos the device read any text off.
  final int read;
  final Map<Outcome, int> outcomes;
  final int sureAndWrong;
  final int rows;

  int get top => outcomes[Outcome.top]!;
  int get candidate => outcomes[Outcome.candidate]!;
  int get wrong => outcomes[Outcome.wrong]!;

  @override
  String toString() =>
      '${name.padRight(22)} 사진 ${'$read'.padLeft(3)} | 첫 줄 정답 ${'$top'.padLeft(3)}'
      ' | 후보 안 ${'$candidate'.padLeft(2)} | 엉뚱한 술 ${'$wrong'.padLeft(2)}'
      ' | 없음 ${'${outcomes[Outcome.none]}'.padLeft(2)}'
      ' | 실패 ${outcomes[Outcome.failed]}'
      ' | 묻지 않고 틀림 ${'$sureAndWrong'.padLeft(2)}'
      ' | 줄 수 평균 ${(rows / photos).toStringAsFixed(1)}';
}

/// The bench's scores by set and device: `shelf/iphone` holds the shelf
/// photos whose drink the catalog has, `shelf-absent/…` those it lacks.
Map<String, BenchScore> scoreBench(List<PhotoResult> results) {
  final groups = <String, List<PhotoResult>>{};
  for (final result in results) {
    final photo = result.photo;
    if (photo.set == 'menu') continue;
    final set = photo.inCatalog ? photo.set : '${photo.set}-absent';
    groups
        .putIfAbsent('$set/${photo.device}', () => <PhotoResult>[])
        .add(result);
  }
  return <String, BenchScore>{
    for (final MapEntry(key: name, value: group) in groups.entries)
      name: BenchScore(name, group),
  };
}

String _explain(PhotoResult result) {
  final out = StringBuffer()
    ..writeln('${result.photo.name}  정답: ${result.photo.truth.join(', ')}')
    ..writeln(
      '결과: ${result.photo.set == 'menu' ? '${result.entriesRight}/${result.photo.truth.length}' : result.outcome.name}',
    );
  final found = result.found;
  if (found == null) return (out..writeln('검색 실패')).toString();
  for (final find in <LabelFind>[...found.finds, ...found.unnamed]) {
    final mark = found.listed.contains(find)
        ? '●'
        : found.finds.contains(find)
        ? '○'
        : '✗';
    out
      ..writeln()
      ..writeln(
        '$mark ${find.group.lines.map((line) => line.text).join(' / ')}',
      )
      ..writeln(
        '  sure=${find.search.sure} tied=${find.search.tied}'
        ' main=${identical(find, found.main)} queries=${find.search.queries}',
      );
    for (final line in find.search.explained) {
      out.writeln('  $line');
    }
  }
  return out.toString();
}

/// The weights with those named in [changes] ("staple=0,known=0") set.
LabelWeights _weights(String changes) {
  final set = <String, double>{
    for (final change in changes.split(','))
      change.split('=').first: double.parse(change.split('=').last),
  };
  const usual = LabelWeights();
  final weights = LabelWeights(
    facts: set.remove('facts') ?? usual.facts,
    placeStep: set.remove('placeStep') ?? usual.placeStep,
    placeUnknown: set.remove('placeUnknown') ?? usual.placeUnknown,
    strength: set.remove('strength') ?? usual.strength,
    strengthElse: set.remove('strengthElse') ?? usual.strengthElse,
    known: set.remove('known') ?? usual.known,
    staple: set.remove('staple') ?? usual.staple,
    candidateShare: set.remove('candidateShare') ?? usual.candidateShare,
    sureShare: set.remove('sureShare') ?? usual.sureShare,
    tieMargin: set.remove('tieMargin') ?? usual.tieMargin,
  );
  if (set.isNotEmpty) throw ArgumentError('no such weight: ${set.keys}');
  return weights;
}

Future<void> main(List<String> args) async {
  final catalog = RecordedCatalog(record: args.contains('--record'));
  final photos = loadBenchPhotos();
  final changed = args.indexOf('--weights');
  final weights = changed < 0
      ? const LabelWeights()
      : _weights(args[changed + 1]);
  final explain = args.indexOf('--explain');
  if (explain >= 0) {
    final wanted = args[explain + 1];
    final chosen = photos.where((photo) => photo.name.startsWith(wanted));
    for (final result in await runBench(
      catalog,
      chosen.toList(),
      weights: weights,
    )) {
      stdout.writeln(_explain(result));
    }
    return;
  }
  final results = await runBench(catalog, photos, weights: weights);
  if (catalog.record) {
    catalog.save();
    stderr.writeln('catalog calls: ${catalog.asked}');
  }
  scoreBench(results).values.forEach(stdout.writeln);
  for (final result in results.where((r) => r.photo.set == 'menu')) {
    stdout.writeln(
      '${result.photo.name.padRight(22)} 항목 ${result.entriesRight}/${result.photo.truth.length}'
      ' | 줄 수 ${result.listed.length}',
    );
  }
  if (args.contains('--photos')) {
    for (final result in results.where((r) => r.photo.set != 'menu')) {
      if (result.photo.lines.isEmpty) continue;
      stdout.writeln(
        '${result.photo.name} ${result.outcome.name}'
        ' ${result.listed.map((find) => '${find.drink.displayName}${find.search.sure
            ? '!'
            : find.search.tied
            ? '?'
            : ''}').join(' | ')}',
      );
    }
  }
}
