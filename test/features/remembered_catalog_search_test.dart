import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/remembered_catalog_search.dart';

import '../support/fake_search.dart';

void main() {
  const balvenie = CatalogDrink(
    id: 'balvenie',
    displayName: '발베니 더블우드 12년',
    category: DrinkCategory.whisky,
  );

  test(
    'a search asked again within the time is answered from memory',
    () async {
      final catalog = FakeCatalog(const <CatalogDrink>[balvenie]);
      var now = DateTime(2026, 11, 10, 12);
      final remembered = RememberedCatalogSearch(catalog, now: () => now);

      expect(await remembered.search('발베니'), <CatalogDrink>[balvenie]);
      // Typed on, then deleted back to the earlier spelling.
      await remembered.search('발베니 더');
      expect(await remembered.search(' 발베니 '), <CatalogDrink>[balvenie]);
      expect(catalog.queries, <String>['발베니', '발베니 더']);

      // Another page of the same name is another question.
      await remembered.search('발베니', offset: 20);
      expect(catalog.queries, hasLength(3));

      now = now.add(const Duration(minutes: 11));
      await remembered.search('발베니');
      expect(
        catalog.queries,
        hasLength(4),
        reason: 'an old answer is asked again',
      );
    },
  );

  test('a failed search is not kept', () async {
    final remembered = RememberedCatalogSearch(FailingCatalog());

    await expectLater(
      remembered.search('발베니'),
      throwsA(isA<CatalogSearchException>()),
    );
    await expectLater(
      remembered.search('발베니'),
      throwsA(isA<CatalogSearchException>()),
    );
  });

  test('only the latest answers are kept', () async {
    final catalog = FakeCatalog(const <CatalogDrink>[balvenie]);
    final remembered = RememberedCatalogSearch(catalog, capacity: 2);

    await remembered.search('가');
    await remembered.search('나');
    await remembered.search('가');
    await remembered.search('다');
    await remembered.search('가');
    await remembered.search('나');

    expect(catalog.queries, <String>['가', '나', '다', '나']);
  });
}
