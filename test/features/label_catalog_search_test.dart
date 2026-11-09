import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_catalog_search.dart';

CatalogDrink _drink(String id) =>
    CatalogDrink(id: id, displayName: id, category: DrinkCategory.whisky);

class _Catalog implements CatalogSearchGateway {
  _Catalog(this.resultsByQuery, {this.failing = const <String>{}});

  final Map<String, List<CatalogDrink>> resultsByQuery;
  final Set<String> failing;
  final List<String> queries = <String>[];

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    queries.add(query);
    if (failing.contains(query)) throw const CatalogSearchException();
    return resultsByQuery[query] ?? const <CatalogDrink>[];
  }
}

void main() {
  group('labelSearchQueries', () {
    test('keeps the naming lines in label order and drops the rest', () {
      expect(
        labelSearchQueries(const <String>[
          'THE BALVENIE',
          '  12  ',
          'DoubleWood',
          'ALC. 40% VOL.',
          '700ml',
          '알코올 17도',
          '40%',
          '',
          'the balvenie',
          'Matured in two distinct casks and bottled by hand at the distillery.',
        ]),
        <String>['BALVENIE', 'DoubleWood'],
      );
    });

    test('drops kind words and the lines made only of them', () {
      expect(
        labelSearchQueries(const <String>[
          'Glenfiddich',
          'SINGLE MALT',
          'SCOTCH WHISKY',
          'AGED 12 YEARS',
          'Glen Grant Single Malt Scotch Whisky',
          '風の森',
          '純米大吟醸',
          '風の森 純米大吟醸',
          '日高見純米',
          '식품유형: 청주',
          '제품명: 닷사이 45',
        ]),
        <String>['Glenfiddich', 'Glen Grant', '風の森', '日高見', '닷사이 45'],
      );
    });

    test('collapses inner whitespace and respects the limit', () {
      expect(
        labelSearchQueries(const <String>['참이슬   후레쉬', '진로', '처음처럼'], limit: 2),
        <String>['참이슬 후레쉬', '진로'],
      );
    });
  });

  group('searchCatalogByLabel', () {
    test('ranks a drink named by several lines above a single hit', () async {
      final balvenie = _drink('balvenie');
      final glenfiddich = _drink('glenfiddich');
      final catalog = _Catalog(<String, List<CatalogDrink>>{
        'BALVENIE': <CatalogDrink>[glenfiddich, balvenie],
        'DoubleWood': <CatalogDrink>[balvenie],
      });

      final matches = await searchCatalogByLabel(catalog, <String>[
        'BALVENIE',
        'DoubleWood',
      ]);

      expect(catalog.queries, <String>['BALVENIE', 'DoubleWood']);
      expect(matches.map((d) => d.id), <String>['balvenie', 'glenfiddich']);
    });

    test('one failed line is tolerated; all failed throws', () async {
      final balvenie = _drink('balvenie');
      final partial = _Catalog(
        <String, List<CatalogDrink>>{
          'BALVENIE': <CatalogDrink>[balvenie],
        },
        failing: <String>{'12년'},
      );
      expect(
        (await searchCatalogByLabel(partial, <String>[
          'BALVENIE',
          '12년',
        ])).map((d) => d.id),
        <String>['balvenie'],
      );

      final broken = _Catalog(
        const <String, List<CatalogDrink>>{},
        failing: <String>{'BALVENIE'},
      );
      expect(
        () => searchCatalogByLabel(broken, <String>['BALVENIE']),
        throwsA(isA<CatalogSearchException>()),
      );
    });
  });
}
