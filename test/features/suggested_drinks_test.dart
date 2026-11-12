import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/suggested_drinks.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';

/// Carries the drinks in [names] and keeps what each call asked for.
class _Catalog implements CatalogSearchGateway {
  _Catalog(this.names);

  final Set<String> names;
  final List<List<String>> calls = <List<String>>[];
  bool failing = false;

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) => throw StateError('the names go out together');

  @override
  Future<List<List<CatalogDrink>>> searchMany(
    List<String> queries, {
    int limit = 10,
    bool readOffLabel = false,
  }) async {
    calls.add(queries);
    if (failing) throw const CatalogSearchException();
    return <List<CatalogDrink>>[
      for (final query in queries)
        <CatalogDrink>[
          // A longer name that also matches is not the suggested drink.
          CatalogDrink(
            id: '$query-gift',
            displayName: '$query 선물세트',
            category: DrinkCategory.whisky,
          ),
          if (names.contains(query))
            CatalogDrink(
              id: query,
              displayName: query,
              category: DrinkCategory.whisky,
            ),
        ],
    ];
  }
}

void main() {
  test('자주 찾는 술 follows the member gender; a guest sees the men list', () {
    expect(
      suggestedDrinkNamesFor(ProfileGender.female),
      femaleSuggestedDrinkNames,
    );
    expect(suggestedDrinkNamesFor(ProfileGender.male), maleSuggestedDrinkNames);
    expect(suggestedDrinkNamesFor(null), maleSuggestedDrinkNames);
    expect(
      suggestedDrinkNamesFor(ProfileGender.other),
      maleSuggestedDrinkNames,
    );
  });

  group('SuggestedDrinks', () {
    setUp(SuggestedDrinks.clear);

    test('looks every name up in one call and keeps the answer', () async {
      final catalog = _Catalog(<String>{'화요 25', '글렌피딕 15년'});
      const names = <String>['화요 25', '없는 술', '글렌피딕 15년'];
      expect(SuggestedDrinks.cached(names), isNull);

      // A second screen asking while the first lookup is on its way shares it.
      final both = await Future.wait(<Future<List<CatalogDrink>>>[
        SuggestedDrinks.load(catalog, names),
        SuggestedDrinks.load(catalog, names),
      ]);

      expect(catalog.calls, <List<String>>[names]);
      expect(both.first.map((d) => d.displayName), <String>[
        '화요 25',
        '글렌피딕 15년',
      ]);
      expect(both.last.map((d) => d.id), both.first.map((d) => d.id));
      expect(SuggestedDrinks.cached(names)?.length, 2);

      // The other list only asks for the names not yet known.
      await SuggestedDrinks.load(catalog, <String>['화요 25', '복순도가 손막걸리']);
      expect(catalog.calls.last, <String>['복순도가 손막걸리']);
    });

    test('a failed lookup is asked again on the next load', () async {
      final catalog = _Catalog(<String>{'화요 25'})..failing = true;
      const names = <String>['화요 25'];

      expect(await SuggestedDrinks.load(catalog, names), isEmpty);
      expect(SuggestedDrinks.cached(names), isNull);

      catalog.failing = false;
      expect(
        (await SuggestedDrinks.load(catalog, names)).single.displayName,
        '화요 25',
      );
      expect(catalog.calls, hasLength(2));
    });
  });
}
