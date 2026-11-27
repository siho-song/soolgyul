import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/discovery_events.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_layout.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_text_recognizer.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';

/// Answers several queries at once with one [search] each, for a fake
/// catalog that only says what a single search finds.
mixin SearchManyByOne implements CatalogSearchGateway {
  @override
  Future<List<List<CatalogDrink>>> searchMany(
    List<String> queries, {
    int limit = 10,
    bool readOffLabel = false,
  }) => Future.wait(queries.map((query) => search(query, limit: limit)));
}

/// Answers every search with the same drinks and keeps the queries.
class FakeCatalog with SearchManyByOne {
  FakeCatalog(this.results);

  final List<CatalogDrink> results;
  final List<String> queries = <String>[];

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    queries.add(query);
    return results;
  }
}

/// Pages [all] by offset and limit and keeps the offsets asked for.
class PagedFakeCatalog with SearchManyByOne {
  PagedFakeCatalog(this.all);

  final List<CatalogDrink> all;
  final List<int> offsets = <int>[];

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    offsets.add(offset);
    return all.skip(offset).take(limit).toList();
  }
}

/// Fails every search.
class FailingCatalog with SearchManyByOne {
  FailingCatalog({this.cause});

  /// What the search failed with; null for a refusal of the server's.
  final Object? cause;

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) {
    throw CatalogSearchException(cause: cause);
  }
}

/// Fails every search while [failing], then answers with [results]; keeps
/// every query either way.
class FlakyCatalog with SearchManyByOne {
  FlakyCatalog(this.results);

  final List<CatalogDrink> results;
  final List<String> queries = <String>[];
  bool failing = true;

  /// What a failing search failed with; null for a refusal of the server's.
  Object? cause;

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    queries.add(query);
    if (failing) throw CatalogSearchException(cause: cause);
    return results;
  }
}

/// [texts] as one label read top to bottom: lines of one size under one
/// another.
List<ReadLine> labelLines(List<String> texts) => <ReadLine>[
  for (final (index, text) in texts.indexed)
    ReadLine(
      text: text,
      left: 0.3,
      top: 0.2 + index * 0.03,
      width: 0.4,
      height: 0.02,
    ),
];

/// Reads the same lines off every photo and keeps the photo paths.
class FakeLabelRecognizer implements LabelTextRecognizer {
  FakeLabelRecognizer(List<String> texts) : lines = labelLines(texts);

  FakeLabelRecognizer.placed(this.lines);

  final List<ReadLine> lines;
  final List<String> paths = <String>[];

  @override
  Future<List<ReadLine>> recognizeLines(String imagePath) async {
    paths.add(imagePath);
    return lines;
  }
}

/// Answers every fit call with [response] and keeps the product ids asked.
class FakeTasteFit implements TasteFitGateway {
  FakeTasteFit(this.response);

  final TasteFitResponse response;
  final List<List<String>> requests = <List<String>>[];

  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    requests.add(productIds);
    return response;
  }
}

/// Keeps every discovery event as `kind surface drink query`.
class FakeDiscoveryEvents implements DiscoveryEventGateway {
  final List<String> events = <String>[];

  @override
  void record(
    DiscoveryEvent event,
    DiscoverySurface surface, {
    String? drinkId,
    String? query,
  }) {
    events.add('${event.key} ${surface.key} $drinkId $query');
  }
}

/// The path every fake label photo is picked from.
const String labelPhotoPath = '/photos/label.jpg';

/// Types [query] into the search field and waits out the typing pause.
Future<void> typeSearch(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextFormField), query);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
  await tester.pump();
}
