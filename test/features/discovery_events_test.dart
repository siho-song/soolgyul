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
  nameEn: 'The Balvenie 12 DoubleWood',
  category: DrinkCategory.whisky,
  styleLabel: '싱글 몰트 위스키',
  abvPercent: 40,
);

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

    await typeSearch(tester, '발베니');
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
    await typeSearch(tester, '동네 막걸리');

    expect(events.events, <String>['search_empty record null 동네 막걸리']);
  });

  testWidgets('a record label read reports its likeliest bottle and the pick', (
    tester,
  ) async {
    final events = FakeDiscoveryEvents();
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        labelTextRecognizer: FakeLabelRecognizer(const <String>[
          'THE BALVENIE',
          'DoubleWood 12',
        ]),
        pickLabelPhoto: () async => XFile(labelPhotoPath),
        discoveryEvents: events,
        onDrinkSelection: (_) {},
      ),
    );
    await tester.pump();

    await _scan(tester, 'drink-search-label-button');
    // The words read go with the bottle, so a wrong match can be traced.
    expect(events.events, <String>[
      'label_match record balvenie-12 BALVENIE DoubleWood 12',
    ]);

    // The bottle chosen from the label carries no typed words; the label
    // pick keeps the words read with it.
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    expect(events.events.skip(1), <String>[
      'search_pick record balvenie-12 null',
      'label_pick record balvenie-12 BALVENIE DoubleWood 12',
    ]);
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
        pickLabelPhoto: () async => XFile(labelPhotoPath),
        discoveryEvents: events,
        onSelect: (_) {},
      ),
    );

    await _scan(tester, 'taste-fit-label-button');

    // The naming lines the catalog was searched with, not the raw label.
    expect(events.events, <String>['label_miss taste_fit null 동네 양조장']);
  });

  testWidgets('a taste-fit label candidate opened is reported as the pick', (
    tester,
  ) async {
    final events = FakeDiscoveryEvents();
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        labelTextRecognizer: FakeLabelRecognizer(const <String>[
          'THE BALVENIE',
          'DoubleWood 12',
        ]),
        pickLabelPhoto: () async => XFile(labelPhotoPath),
        discoveryEvents: events,
        onSelect: (_) {},
      ),
    );

    await _scan(tester, 'taste-fit-label-button');
    await tester.tap(find.text(_balvenie.displayName).first);

    expect(events.events, <String>[
      'label_match taste_fit balvenie-12 BALVENIE DoubleWood 12',
      'label_pick taste_fit balvenie-12 BALVENIE DoubleWood 12',
      'fit_view taste_fit balvenie-12 null',
    ]);
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

    await typeSearch(tester, '발베니');
    await tester.tap(find.text(_balvenie.displayName));

    expect(events.events, <String>[
      'search_pick taste_fit balvenie-12 발베니',
      'fit_view taste_fit balvenie-12 null',
    ]);
  });
}
