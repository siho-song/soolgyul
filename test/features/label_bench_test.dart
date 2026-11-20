import 'package:flutter_test/flutter_test.dart';

import '../../tools/label_bench/label_bench.dart';

// What the label search makes of the bench's photos (`tools/label_bench`):
// shop shelves, product photos and a wine list, as phones read them, with
// the catalog as it answered when recorded. Each number is what the search
// reaches now; a change that lowers one fails here, and one that raises
// one moves the number up with it.
void main() {
  late Map<String, BenchScore> scores;
  late List<PhotoResult> results;

  setUpAll(() async {
    results = await runBench(RecordedCatalog(), loadBenchPhotos());
    scores = scoreBench(results);
  });

  test('a shelf photo lists the bottle it is of', () {
    final iphone = scores['shelf/iphone']!;
    expect(iphone.read, 23);
    expect(iphone.top, greaterThanOrEqualTo(16));
    expect(iphone.wrong, lessThanOrEqualTo(4));

    final android = scores['shelf/android']!;
    expect(android.top, greaterThanOrEqualTo(10));
    expect(android.wrong, lessThanOrEqualTo(8));
  });

  test('a product photo finds its bottle, and seldom lists another without '
      'asking', () {
    final bottles = scores['bottle/iphone']!;
    expect(bottles.read, 132);
    expect(bottles.top, greaterThanOrEqualTo(66));
    expect(bottles.wrong, lessThanOrEqualTo(21));
    expect(bottles.sureAndWrong, lessThanOrEqualTo(6));
  });

  test('a wine list lists its entries', () {
    final entries = <String, int>{
      for (final result in results.where((r) => r.photo.set == 'menu'))
        result.photo.device: result.entriesRight,
    };
    expect(entries['iphone'], greaterThanOrEqualTo(8));
    expect(entries['android'], greaterThanOrEqualTo(7));
  });
}
