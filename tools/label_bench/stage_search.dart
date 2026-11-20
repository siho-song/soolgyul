// Searches each cut-out object of a photo as a photo of its own (the
// object found by a detector, cut out and enlarged, then read) and keeps
// the drinks found, the one nearest the cut-out's middle first.
//
//   dart run tools/label_bench/stage_search.dart <reads.json> <out.json>
//       [--record] [--answers <file under data/>]
import 'dart:convert';
import 'dart:io';

import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_catalog_search.dart';

import 'label_bench.dart';

Future<void> main(List<String> args) async {
  final reads =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final answers = args.indexOf('--answers');
  final catalog = RecordedCatalog(
    record: args.contains('--record'),
    file: answers >= 0 ? args[answers + 1] : 'stage_answers.json.gz',
  );
  Map<String, Object?> find(LabelFind find) => <String, Object?>{
    'sure': find.search.sure,
    'tied': find.search.tied,
    'share': find.search.share,
    'score': find.search.score,
    'offCentre': find.group.offCentre,
    'matches': find.search.matches.take(5).map((d) => d.displayName).toList(),
  };
  final out = <String, Object?>{};
  for (final MapEntry(key: id, value: lines) in reads.entries) {
    if ((lines as List).isEmpty) continue;
    PhotoSearch? found;
    try {
      found = await searchCatalogByPhoto(catalog, benchLines(lines));
    } on CatalogSearchException {
      found = null;
    }
    final main = found?.main;
    out[id] = found == null
        ? null
        : <String, Object?>{
            'main': main == null ? null : find(main),
            'finds': found.finds.map(find).toList(),
          };
    if (out.length % 100 == 0) {
      if (catalog.record) catalog.save();
      stderr.writeln('${out.length}, calls ${catalog.asked}');
    }
  }
  if (catalog.record) catalog.save();
  File(args[1]).writeAsStringSync(jsonEncode(out));
}
