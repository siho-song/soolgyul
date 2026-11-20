// Runs the label match (label_match.dart) on read units whose catalog
// answers were recorded: each unit's read lines, what the line search made
// of it, and the rows the label word search answered (match/ask_db.py).
// Writes what the match decided for each unit, for match/grade.py.
//
//   dart run tools/label_bench/match_stage.dart
//       [units.json.gz] [rows.json.gz] [out.json]
//
// By default the units of data/match_units.json.gz, the rows of
// match/.cache/rows.json.gz and match/.cache/dart_out.json.
//
// A unit is {"id", "set": "one" | "cut", "lines": [[text, left, top, width,
// height, confidence]], "app": [{"names", "first", "sure", "tied"}]}; the
// rows are {unit id: [row as the search function answers it]}.
import 'dart:convert';
import 'dart:io';

import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_match.dart';

import 'label_bench.dart';

LabelCandidate candidateOf(Map<String, dynamic> row) => LabelCandidate(
  drink: CatalogDrink(
    id: row['id'] as String,
    displayName: row['name_ko'] as String,
    nameEn: row['name_en'] as String?,
    category: DrinkCategory.other,
    abvPercent: (row['abv_percent'] as num?)?.toDouble(),
    labelFacts: DrinkLabelFacts.fromJson(row['label_facts']),
  ),
  kind: row['category_key'] as String,
  nameRarity: <String, double>{
    for (final MapEntry(:key, :value)
        in ((row['name_rarity'] as Map?) ?? const {}).entries)
      key as String: (value as num).toDouble(),
  },
  found: (row['found'] as num).toDouble(),
);

Object? _gzipJson(String path) =>
    jsonDecode(utf8.decode(gzip.decode(File(path).readAsBytesSync())));

void main(List<String> args) {
  String arg(int index, String fallback) =>
      args.length > index ? args[index] : fallback;
  const here = 'tools/label_bench';
  final units = _gzipJson(arg(0, '$here/data/match_units.json.gz'))! as List;
  final rows =
      _gzipJson(arg(1, '$here/match/.cache/rows.json.gz'))!
          as Map<String, dynamic>;
  final out = <String, Object?>{};
  final watch = Stopwatch()..start();
  for (final unit in units.cast<Map<String, dynamic>>()) {
    final id = unit['id'] as String;
    final match = rankLabelMatch(
      benchLines(unit['lines']),
      <LabelCandidate>[
        for (final row in (rows[id] as List? ?? const []))
          candidateOf(row as Map<String, dynamic>),
      ],
      lineFinds: <LineFind>[
        for (final find in (unit['app'] as List? ?? const []).cast<Map>())
          LineFind(
            names: (find['names'] as List).cast<String>(),
            first: find['first'] == true,
            sure: find['sure'] == true,
            tied: find['tied'] == true,
          ),
      ],
      cut: unit['set'] == 'cut',
    );
    out[id] = <String, Object?>{
      'state': match.state.name,
      'sureness': match.sureness,
      'drinks': match.drinks
          .take(5)
          .map((d) => drinkOfName(d.displayName))
          .toList(),
    };
  }
  stderr.writeln(
    '${out.length} units, ${watch.elapsedMilliseconds / out.length} ms a unit',
  );
  File(
    arg(2, '$here/match/.cache/dart_out.json'),
  ).writeAsStringSync(jsonEncode(out));
}
