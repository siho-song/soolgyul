import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/recording/presentation/drink_search_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';

import '../support/app_test_harness.dart';
import '../support/fake_search.dart';

const _balvenie = CatalogDrink(
  id: 'balvenie-12',
  displayName: '발베니 12년 더블우드',
  category: DrinkCategory.whisky,
  styleLabel: '싱글 몰트 위스키',
  abvPercent: 40,
);

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextFormField), query);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
  await tester.pump();
}

Future<void> _scan(WidgetTester tester, String buttonKey) async {
  await tester.tap(find.byKey(ValueKey<String>(buttonKey)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a record pick is reported with the words typed for it', (
    tester,
  ) async {
    final events = FakeDiscoveryEvents();
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        discoveryEvents: events,
        onDrinkSelection: (_) {},
      ),
    );

    await _type(tester, '발베니');
    await tester.tap(find.text(_balvenie.displayName));
    await tester.pumpAndSettle();
    expect(events.events, isEmpty, reason: 'a tap alone is not a pick');

    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    expect(events.events, <String>['search_pick record balvenie-12 발베니']);
  });

  testWidgets('a search that finds nothing is reported once it settles', (
    tester,
  ) async {
    final events = FakeDiscoveryEvents();
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[]),
        discoveryEvents: events,
        onDrinkSelection: (_) {},
      ),
    );

    await tester.enterText(find.byType(TextFormField), '동네');
    await tester.pump(const Duration(milliseconds: 100));
    await _type(tester, '동네 막걸리');

    expect(events.events, <String>['search_empty record null 동네 막걸리']);
  });

  testWidgets('a record label read reports its likeliest bottle', (
    tester,
  ) async {
    final events = FakeDiscoveryEvents();
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        labelTextRecognizer: FakeLabelRecognizer(const <String>[
          'THE BALVENIE',
        ]),
        pickLabelPhoto: () async => XFile('/photos/label.jpg'),
        discoveryEvents: events,
        onDrinkSelection: (_) {},
      ),
    );
    await tester.pump();

    await _scan(tester, 'drink-search-label-button');
    expect(events.events, <String>['label_match record balvenie-12 null']);

    // The bottle chosen from the label carries no typed words.
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    expect(events.events.last, 'search_pick record balvenie-12 null');
  });

  testWidgets('a taste-fit label nobody matches reports the words read', (
    tester,
  ) async {
    final events = FakeDiscoveryEvents();
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[]),
        labelTextRecognizer: FakeLabelRecognizer(const <String>['동네 양조장 막걸리']),
        pickLabelPhoto: () async => XFile('/photos/label.jpg'),
        discoveryEvents: events,
        onSelect: (_) {},
      ),
    );

    await _scan(tester, 'taste-fit-label-button');

    // The naming lines the catalog was searched with, not the raw label.
    expect(events.events, <String>['label_miss taste_fit null 동네 양조장']);
  });

  testWidgets('opening a fit from the results reports the pick and the view', (
    tester,
  ) async {
    final events = FakeDiscoveryEvents();
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        discoveryEvents: events,
        onSelect: (_) {},
      ),
    );

    await _type(tester, '발베니');
    await tester.tap(find.text(_balvenie.displayName));

    expect(events.events, <String>[
      'search_pick taste_fit balvenie-12 발베니',
      'fit_view taste_fit balvenie-12 null',
    ]);
  });
}
