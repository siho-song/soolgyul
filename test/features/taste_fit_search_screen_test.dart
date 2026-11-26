import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/suggested_drinks.dart';
import 'package:soolgyul/src/features/recording/presentation/widgets/selected_drink_card.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_layout.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_match.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_text_recognizer.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/label_scan_button.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_badge.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';
import 'package:soolgyul/src/widgets/app_state_view.dart';

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

const _caution = CatalogDrink(
  id: 'ardbeg-10',
  displayName: '아드벡 10년',
  category: DrinkCategory.whisky,
  styleLabel: '싱글 몰트 위스키',
  abvPercent: 46,
);

const _neutral = CatalogDrink(
  id: 'glenfiddich-12',
  displayName: '글렌피딕 12년',
  category: DrinkCategory.whisky,
  styleLabel: '싱글 몰트 위스키',
  abvPercent: 40,
);

/// The front of a Balvenie bottle as a phone reads it.
const _balvenieLabel = <String>['THE BALVENIE', 'DoubleWood 12'];

const _noInfo = CatalogDrink(
  id: 'mystery',
  displayName: '정보 없는 술',
  category: DrinkCategory.other,
);

/// The row heart read aloud as [label]; the row folds it into its own label.
Finder _badge(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

TasteFitVerdict _verdict(String id, TasteFitBadge badge) =>
    TasteFitVerdict(productId: id, badge: badge, headline: 'headline');

void main() {
  testWidgets('results carry the badge of each verdict', (tester) async {
    final fit = FakeTasteFit(
      TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{
          _balvenie.id: _verdict(_balvenie.id, TasteFitBadge.star),
          _caution.id: _verdict(_caution.id, TasteFitBadge.caution),
          _neutral.id: _verdict(_neutral.id, TasteFitBadge.neutral),
          _noInfo.id: _verdict(_noInfo.id, TasteFitBadge.noInfo),
        },
      ),
    );
    final catalog = FakeCatalog(const <CatalogDrink>[
      _balvenie,
      _caution,
      _neutral,
      _noInfo,
    ]);
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: catalog,
        tasteFitGateway: fit,
        onSelect: (_) {},
      ),
    );

    await typeSearch(tester, '발베니');

    expect(catalog.queries, <String>['발베니']);
    expect(fit.requests, <List<String>>[
      <String>[_balvenie.id, _caution.id, _neutral.id, _noInfo.id],
    ]);
    expect(find.text('발베니 12년 더블우드'), findsOneWidget);
    expect(_badge('취향 저격'), findsOneWidget);
    expect(_badge('아쉬울 수 있어요'), findsOneWidget);
    expect(_badge('편안해요'), findsOneWidget);
    expect(find.byType(TasteFitRowBadge), findsNWidgets(4));
    expect(
      find.byWidgetPredicate(
        (w) => w is TasteFitBadgeIcon && w.badge == TasteFitBadge.star,
      ),
      findsOneWidget,
    );
    // A smile, a frown and a plain face for the three verdicts; none for no_info.
    expect(
      find.byWidgetPredicate(
        (w) => w is TasteFitBadgeIcon && w.badge == TasteFitBadge.caution,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is TasteFitBadgeIcon && w.badge == TasteFitBadge.neutral,
      ),
      findsOneWidget,
    );
    expect(find.text(tasteFitNoCardsHint), findsNothing);
  });

  testWidgets('scrolling to the end loads the next page of matches', (
    tester,
  ) async {
    final drinks = <CatalogDrink>[
      for (var n = 1; n <= 25; n++)
        CatalogDrink(
          id: 'drink-$n',
          displayName: '발베니 $n',
          category: DrinkCategory.whisky,
        ),
    ];
    final catalog = PagedFakeCatalog(drinks);
    final fit = FakeTasteFit(
      TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{
          'drink-25': _verdict('drink-25', TasteFitBadge.star),
        },
      ),
    );
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: catalog,
        tasteFitGateway: fit,
        onSelect: (_) {},
      ),
    );

    await typeSearch(tester, '발베니');
    expect(catalog.offsets, <int>[0]);

    await tester.dragUntilVisible(
      find.text('발베니 25'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(catalog.offsets, <int>[0, 20]);
    expect(fit.requests.last, <String>[
      for (var n = 21; n <= 25; n++) 'drink-$n',
    ]);
    expect(find.byType(TasteFitRowBadge), findsOneWidget);

    // A short page is the last one: scrolling further asks for nothing.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(catalog.offsets, <int>[0, 20]);
  });

  testWidgets('without saved cards the hint shows and no badge does', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        tasteFitGateway: FakeTasteFit(
          TasteFitResponse(
            hasCards: false,
            verdicts: <String, TasteFitVerdict>{
              _balvenie.id: _verdict(_balvenie.id, TasteFitBadge.star),
            },
          ),
        ),
        onSelect: (_) {},
      ),
    );

    await typeSearch(tester, '발베니');

    expect(find.text('발베니 12년 더블우드'), findsOneWidget);
    expect(find.text(tasteFitNoCardsHint), findsOneWidget);
    expect(find.byType(TasteFitRowBadge), findsNothing);
    expect(_badge('취향 저격'), findsNothing);
  });

  testWidgets('a failed fit call still lists the results', (tester) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        tasteFitGateway: _FailingFitGateway(),
        onSelect: (_) {},
      ),
    );

    await typeSearch(tester, '발베니');

    expect(find.text('발베니 12년 더블우드'), findsOneWidget);
    expect(find.byType(TasteFitRowBadge), findsNothing);
    expect(find.text(tasteFitNoCardsHint), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a row hands over the drink and its verdict', (
    tester,
  ) async {
    final selections = <TasteFitSelection>[];
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        tasteFitGateway: FakeTasteFit(
          TasteFitResponse(
            hasCards: true,
            verdicts: <String, TasteFitVerdict>{
              _balvenie.id: _verdict(_balvenie.id, TasteFitBadge.star),
            },
          ),
        ),
        onSelect: selections.add,
      ),
    );

    await typeSearch(tester, '발베니');
    await tester.tap(find.text('발베니 12년 더블우드'));
    await tester.pump();

    expect(selections, hasLength(1));
    expect(selections.single.drink.id, _balvenie.id);
    expect(selections.single.verdict?.badge, TasteFitBadge.star);
    expect(selections.single.hasCards, isTrue);
  });

  testWidgets('no match says so and an empty query shows the prompt', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[]),
        onSelect: (_) {},
      ),
    );

    expect(find.text('찾으시는 술의 이름을 검색해 보세요.'), findsOneWidget);
    await typeSearch(tester, '없는 술');
    expect(find.text('일치하는 술이 없어요. 다른 이름으로 검색해 보세요.'), findsOneWidget);

    await tester.tap(find.byTooltip('입력 내용 삭제'));
    await tester.pump();
    expect(find.text('찾으시는 술의 이름을 검색해 보세요.'), findsOneWidget);
  });

  testWidgets('suggested drinks show with their badges before any search', (
    tester,
  ) async {
    addTearDown(SuggestedDrinks.clear);
    final catalog = FakeCatalog(const <CatalogDrink>[_balvenie]);
    final fit = FakeTasteFit(
      TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{
          _balvenie.id: _verdict(_balvenie.id, TasteFitBadge.star),
        },
      ),
    );
    TasteFitSelection? picked;
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: catalog,
        tasteFitGateway: fit,
        suggestedDrinkNames: <String>[_balvenie.displayName],
        onSelect: (selection) => picked = selection,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(tasteFitSuggestionsTitle), findsOneWidget);
    expect(find.text(_balvenie.displayName), findsOneWidget);
    expect(_badge('취향 저격'), findsOneWidget);
    expect(fit.requests, <List<String>>[
      <String>[_balvenie.id],
    ]);

    await tester.tap(find.text(_balvenie.displayName));
    expect(picked?.drink.id, _balvenie.id);
    expect(picked?.verdict?.badge, TasteFitBadge.star);
    expect(picked?.judged, isTrue);

    // A search replaces the list; clearing it brings the suggestions back.
    await typeSearch(tester, '아드벡');
    expect(find.text(tasteFitSuggestionsTitle), findsNothing);
    await tester.tap(find.byTooltip('입력 내용 삭제'));
    await tester.pump();
    expect(find.text(tasteFitSuggestionsTitle), findsOneWidget);
  });

  testWidgets('a suggestion tapped before its badge is handed over unjudged', (
    tester,
  ) async {
    addTearDown(SuggestedDrinks.clear);
    TasteFitSelection? picked;
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        tasteFitGateway: _SlowFitGateway(),
        suggestedDrinkNames: <String>[_balvenie.displayName],
        onSelect: (selection) => picked = selection,
      ),
    );
    await tester.pumpAndSettle();
    // The list waits a second for its faces, then shows without them.
    expect(find.text(_balvenie.displayName), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_balvenie.displayName), findsOneWidget);
    expect(_badge('취향 저격'), findsNothing);

    await tester.tap(find.text(_balvenie.displayName));
    expect(picked?.verdict, isNull);
    expect(picked?.judged, isFalse);
  });

  testWidgets('a label that names a brand and not which bottle lists the '
      'brand\'s bottles to choose from', (tester) async {
    const m = CatalogDrink(
      id: 'montes-m',
      displayName: '몬테스 알파 M 2021',
      nameEn: 'Montes Alpha M',
      category: DrinkCategory.redWine,
    );
    const syrah = CatalogDrink(
      id: 'montes-syrah',
      displayName: '몬테스 알파 시라',
      nameEn: 'Montes Alpha Syrah',
      category: DrinkCategory.redWine,
    );
    await _scanLabel(
      tester,
      lines: const <String>['MONTES ALPHA', '2022'],
      catalog: FakeCatalog(const <CatalogDrink>[m, syrah]),
    );

    expect(find.text(tasteFitLabelTiedHint), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('label-best-candidate')),
      findsNothing,
    );
    expect(find.text(m.displayName), findsOneWidget);
    expect(find.text(syrah.displayName), findsOneWidget);
  });

  testWidgets('a brand-only bottle beside a drink read whole shows the '
      'drink, then the brand\'s bottles', (tester) async {
    const m = CatalogDrink(
      id: 'montes-m',
      displayName: '몬테스 알파 M 2021',
      nameEn: 'Montes Alpha M',
      category: DrinkCategory.redWine,
    );
    const syrah = CatalogDrink(
      id: 'montes-syrah',
      displayName: '몬테스 알파 시라',
      nameEn: 'Montes Alpha Syrah',
      category: DrinkCategory.redWine,
    );
    final fit = FakeTasteFit(
      const TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{},
      ),
    );
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: FakeLabelRecognizer.placed(const <ReadLine>[
        ReadLine(
          text: 'MONTES ALPHA',
          left: 0.35,
          top: 0.50,
          width: 0.3,
          height: 0.06,
        ),
        ReadLine(text: '아드벡', left: 0.02, top: 0.50, width: 0.2, height: 0.05),
        ReadLine(text: '10년', left: 0.06, top: 0.57, width: 0.1, height: 0.03),
      ]),
      catalog: FakeCatalog(const <CatalogDrink>[_caution, m, syrah]),
      fit: fit,
    );

    expect(find.text(tasteFitLabelTiedHint), findsNothing);
    final hint = tester.getTopLeft(find.text(tasteFitLabelTiedAmongHint)).dy;
    expect(
      tester.getTopLeft(find.text(_caution.displayName)).dy,
      lessThan(hint),
    );
    for (final bottle in <CatalogDrink>[m, syrah]) {
      expect(
        tester.getTopLeft(find.text(bottle.displayName)).dy,
        greaterThan(hint),
      );
    }
    // Every row shown is judged, the brand's bottles too.
    expect(
      fit.requests.single,
      unorderedEquals(<String>[_caution.id, m.id, syrah.id]),
    );
  });

  testWidgets('a photo of several drinks lists them, best fit first', (
    tester,
  ) async {
    final fit = FakeTasteFit(
      TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{
          _caution.id: _verdict(_caution.id, TasteFitBadge.caution),
          _neutral.id: _verdict(_neutral.id, TasteFitBadge.neutral),
        },
      ),
    );
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: FakeLabelRecognizer.placed(_twoBottles()),
      catalog: FakeCatalog(const <CatalogDrink>[_caution, _neutral]),
      fit: fit,
    );

    expect(find.byKey(const ValueKey<String>('label-several')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('label-best-candidate')),
      findsNothing,
    );
    // 아드벡 is the left bottle; 글렌피딕 fits better and comes first.
    expect(
      tester.getTopLeft(find.text(_neutral.displayName)).dy,
      lessThan(tester.getTopLeft(find.text(_caution.displayName)).dy),
    );
    expect(fit.requests.single, <String>[_caution.id, _neutral.id]);
    expect(find.byType(TasteFitRowBadge), findsNWidgets(2));
  });

  testWidgets('several drinks without verdicts keep the photo\'s order', (
    tester,
  ) async {
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: FakeLabelRecognizer.placed(_twoBottles()),
      catalog: FakeCatalog(const <CatalogDrink>[_caution, _neutral]),
    );

    expect(
      tester.getTopLeft(find.text(_caution.displayName)).dy,
      lessThan(tester.getTopLeft(find.text(_neutral.displayName)).dy),
    );
  });

  testWidgets('a photo the detector cuts into bottles lists each bottle, '
      'left to right', (tester) async {
    final recognizer = FakeBottleReader(<BottleCut>[
      bottleCut(0.55, const <String>['글렌피딕', '12년']),
      bottleCut(0.05, const <String>['아드벡', '10년']),
    ]);
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: recognizer,
      catalog: _ByNameCatalog(const <String, CatalogDrink>{
        '아드벡': _caution,
        '글렌피딕': _neutral,
      }),
    );

    expect(find.byKey(const ValueKey<String>('label-several')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(_caution.displayName)).dy,
      lessThan(tester.getTopLeft(find.text(_neutral.displayName)).dy),
    );
    expect(recognizer.wholeReads, 0);
  });

  testWidgets('a photo with fewer than two drinks found is read whole', (
    tester,
  ) async {
    final recognizer = FakeBottleReader(const <BottleCut>[]);
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: recognizer,
      catalog: FakeCatalog(const <CatalogDrink>[_balvenie]),
    );

    expect(recognizer.wholeReads, 1);
    expect(find.text(_balvenie.displayName), findsWidgets);
  });

  testWidgets('a detector that fails leaves the whole photo to read', (
    tester,
  ) async {
    final recognizer = FakeBottleReader(null);
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: recognizer,
      catalog: FakeCatalog(const <CatalogDrink>[_balvenie]),
    );

    expect(recognizer.wholeReads, 1);
    expect(find.text(_balvenie.displayName), findsWidgets);
  });

  testWidgets('cut-out bottles are matched by their words without the line '
      'search', (tester) async {
    final catalog = _WordCatalog(const <CatalogDrink>[], <LabelCandidate>[
      _wordCandidate(_balvenie),
    ]);
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: FakeBottleReader(<BottleCut>[
        bottleCut(0.05, const <String>['THE BALVENIE', 'DOUBLEWOOD']),
        bottleCut(0.55, const <String>['THE BALVENIE', 'DOUBLEWOOD']),
      ]),
      catalog: catalog,
    );

    expect(catalog.queries, isEmpty);
    expect(catalog.words, contains('balvenie'));
    expect(find.text(_balvenie.displayName), findsWidgets);
  });

  group('a list waits for its faces', () {
    final starred = TasteFitResponse(
      hasCards: true,
      verdicts: <String, TasteFitVerdict>{
        _balvenie.id: _verdict(_balvenie.id, TasteFitBadge.star),
      },
    );

    Future<_GatedFitGateway> pumpSearch(
      WidgetTester tester, {
      List<String> suggestedDrinkNames = const <String>[],
    }) async {
      final fit = _GatedFitGateway();
      await pumpTestScreen(
        tester,
        TasteFitSearchScreen(
          catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
          tasteFitGateway: fit,
          suggestedDrinkNames: suggestedDrinkNames,
          onSelect: (_) {},
        ),
      );
      return fit;
    }

    testWidgets('a fast answer shows the rows and their faces together', (
      tester,
    ) async {
      final fit = await pumpSearch(tester);
      await typeSearch(tester, '발베니');

      // Searching still shows while the faces are on the way.
      expect(fit.calls, hasLength(1));
      expect(find.text(_balvenie.displayName), findsNothing);
      expect(find.byType(AppSmallSpinner), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_balvenie.displayName), findsNothing);

      fit.calls.single.complete(starred);
      await tester.pump();
      expect(find.text(_balvenie.displayName), findsOneWidget);
      expect(_badge('취향 저격'), findsOneWidget);
      expect(find.byType(AppSmallSpinner), findsNothing);
    });

    testWidgets('a slow answer shows the rows after a second, then the faces', (
      tester,
    ) async {
      final fit = await pumpSearch(tester);
      await typeSearch(tester, '발베니');

      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text(_balvenie.displayName), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(_balvenie.displayName), findsOneWidget);
      expect(find.byType(TasteFitRowBadge), findsNothing);

      fit.calls.single.complete(starred);
      await tester.pump();
      expect(_badge('취향 저격'), findsOneWidget);
    });

    testWidgets('the suggestions wait for their faces too', (tester) async {
      addTearDown(SuggestedDrinks.clear);
      final fit = await pumpSearch(
        tester,
        suggestedDrinkNames: <String>[_balvenie.displayName],
      );
      await tester.pump();
      expect(fit.calls, hasLength(1));
      expect(find.text(_balvenie.displayName), findsNothing);

      fit.calls.single.complete(starred);
      await tester.pump();
      expect(find.text(_balvenie.displayName), findsOneWidget);
      expect(_badge('취향 저격'), findsOneWidget);
    });

    testWidgets('a reader without cards waits no more once that is known', (
      tester,
    ) async {
      final fit = await pumpSearch(tester);
      await typeSearch(tester, '발베니');
      fit.calls.single.complete(
        const TasteFitResponse(
          hasCards: false,
          verdicts: <String, TasteFitVerdict>{},
        ),
      );
      await tester.pump();
      expect(find.text(_balvenie.displayName), findsOneWidget);

      await typeSearch(tester, '발베니 12');
      expect(fit.calls, hasLength(2));
      expect(find.text(_balvenie.displayName), findsOneWidget);
      expect(find.byType(AppSmallSpinner), findsNothing);
    });

    testWidgets('without a fit call the rows show at once', (tester) async {
      await pumpTestScreen(
        tester,
        TasteFitSearchScreen(
          catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
          onSelect: (_) {},
        ),
      );
      await typeSearch(tester, '발베니');

      expect(find.text(_balvenie.displayName), findsOneWidget);
      expect(find.byType(AppSmallSpinner), findsNothing);
    });
  });

  testWidgets('without a recognizer there is no label button', (tester) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[]),
        onSelect: (_) {},
      ),
    );
    expect(find.text(tasteFitLabelButtonLabel), findsNothing);
  });

  testWidgets('a label photo searches its naming lines and badges the rows', (
    tester,
  ) async {
    final catalog = FakeCatalog(const <CatalogDrink>[_balvenie]);
    final fit = FakeTasteFit(
      TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{
          _balvenie.id: _verdict(_balvenie.id, TasteFitBadge.star),
        },
      ),
    );
    final recognizer = FakeLabelRecognizer(const <String>[
      'THE BALVENIE',
      'DoubleWood',
      'ALC. 40% VOL.',
    ]);
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: recognizer,
      catalog: catalog,
      fit: fit,
    );

    expect(recognizer.paths, <String>[labelPhotoPath]);
    expect(catalog.queries, <String>[
      'BALVENIE',
      'DoubleWood',
      'BALVENIE DoubleWood',
    ]);
    expect(find.text('찾으시는 술이 맞나요?'), findsOneWidget);
    expect(find.textContaining('라벨에서 읽은 글자'), findsNothing);
    expect(find.text('발베니 12년 더블우드'), findsOneWidget);
    // The card carries the detail's verdict line.
    expect(find.text('headline'), findsOneWidget);
    expect(fit.requests, <List<String>>[
      <String>[_balvenie.id],
    ]);

    // Typing again leaves the label behind.
    await typeSearch(tester, '아드벡');
    expect(find.text('찾으시는 술이 맞나요?'), findsNothing);
  });

  testWidgets('a label asks about its likeliest bottle above the others', (
    tester,
  ) async {
    TasteFitSelection? picked;
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[
          _balvenie,
          _neutral,
        ]),
        labelTextRecognizer: FakeLabelRecognizer(const <String>[
          'THE BALVENIE',
          'DoubleWood 12',
          '글렌피딕 12년',
        ]),
        pickLabelPhoto: () async => XFile(labelPhotoPath),
        onSelect: (selection) => picked = selection,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('taste-fit-label-button')),
    );
    await tester.pumpAndSettle();

    final best = find.byKey(const ValueKey<String>('label-best-candidate'));
    final others = find.byKey(const ValueKey<String>('label-other-candidates'));
    expect(
      find.descendant(of: best, matching: find.text(_balvenie.displayName)),
      findsOneWidget,
    );
    expect(find.text(otherCandidatesTitle), findsOneWidget);
    expect(
      find.descendant(of: others, matching: find.text(_neutral.displayName)),
      findsOneWidget,
    );

    // The card opens the bottle, and says so with the rows' chevron.
    expect(
      find.descendant(
        of: best,
        matching: find.byWidgetPredicate(
          (w) => w is AppIcon && w.icon == AppIconAsset.next,
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(best);
    expect(picked?.drink.id, _balvenie.id);
  });

  testWidgets('the label match ranks the bottle above what the line search '
      'put first', (tester) async {
    final catalog = _WordCatalog(
      const <CatalogDrink>[_neutral, _balvenie],
      <LabelCandidate>[_wordCandidate(_neutral), _wordCandidate(_balvenie)],
    );
    await _scanLabel(tester, lines: _balvenieLabel, catalog: catalog);

    expect(catalog.words, contains('balvenie'));
    final best = find.byKey(const ValueKey<String>('label-best-candidate'));
    expect(
      find.descendant(of: best, matching: find.text(_balvenie.displayName)),
      findsOneWidget,
    );
  });

  testWidgets('a failed word search leaves the line search\'s answer', (
    tester,
  ) async {
    final catalog = _WordCatalog(const <CatalogDrink>[_balvenie], null);
    await _scanLabel(tester, lines: _balvenieLabel, catalog: catalog);

    final best = find.byKey(const ValueKey<String>('label-best-candidate'));
    expect(
      find.descendant(of: best, matching: find.text(_balvenie.displayName)),
      findsOneWidget,
    );
  });

  testWidgets('a card that is no button carries no chevron', (tester) async {
    await pumpTestScreen(tester, const SelectedDrinkCard(drink: _balvenie));

    expect(find.text(_balvenie.displayName), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == AppIconAsset.next,
      ),
      findsNothing,
    );
  });

  testWidgets('a search on the wire shows in the field and leaves the rows '
      'where they are', (tester) async {
    final catalog = _GatedCatalog(const <CatalogDrink>[_balvenie, _neutral]);
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(catalogSearchGateway: catalog, onSelect: (_) {}),
    );
    final spinner = find.byKey(
      const ValueKey<String>('app-text-field-loading'),
    );

    await typeSearch(tester, '발베니');
    expect(spinner, findsOneWidget);
    catalog.calls.single.complete();
    await tester.pump();
    expect(spinner, findsNothing);
    final row = tester.getTopLeft(find.text(_balvenie.displayName));

    await typeSearch(tester, '발베니 12');
    expect(spinner, findsOneWidget);
    expect(tester.getTopLeft(find.text(_balvenie.displayName)), row);
    catalog.calls.last.complete();
    await tester.pump();
    expect(spinner, findsNothing);
    expect(tester.getTopLeft(find.text(_balvenie.displayName)), row);
  });

  testWidgets('a saved record asks for the faces on screen again', (
    tester,
  ) async {
    addTearDown(SuggestedDrinks.clear);
    final fit = _ChangingFit(
      const TasteFitResponse(
        hasCards: false,
        verdicts: <String, TasteFitVerdict>{},
      ),
    );
    Widget screen(int revision) => TasteFitSearchScreen(
      catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
      tasteFitGateway: fit,
      suggestedDrinkNames: <String>[_balvenie.displayName],
      revision: revision,
      onSelect: (_) {},
    );
    await pumpTestScreen(tester, screen(0));
    await tester.pumpAndSettle();
    expect(find.byType(TasteFitRowBadge), findsNothing);
    await typeSearch(tester, '발베니');
    expect(find.text(tasteFitNoCardsHint), findsOneWidget);
    expect(fit.requests, hasLength(2));

    // The reader's first record was saved over this page.
    fit.response = TasteFitResponse(
      hasCards: true,
      verdicts: <String, TasteFitVerdict>{
        _balvenie.id: _verdict(_balvenie.id, TasteFitBadge.star),
      },
    );
    await pumpTestScreen(tester, screen(1));
    await tester.pumpAndSettle();

    // The suggestions and the results each asked again.
    expect(fit.requests, hasLength(4));
    expect(find.text(tasteFitNoCardsHint), findsNothing);
    expect(_badge('취향 저격'), findsOneWidget);

    await tester.tap(find.byTooltip('입력 내용 삭제'));
    await tester.pumpAndSettle();
    expect(find.text(tasteFitSuggestionsTitle), findsOneWidget);
    expect(_badge('취향 저격'), findsOneWidget);
  });

  testWidgets('✕ empties the field and brings the keyboard back', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        onSelect: (_) {},
      ),
    );
    await typeSearch(tester, '발베니');
    final field = tester.widget<EditableText>(find.byType(EditableText));
    // The reader dragged the list, which puts the keyboard away.
    field.focusNode.unfocus();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.byTooltip('입력 내용 삭제'));
    await tester.pumpAndSettle();

    expect(field.controller.text, isEmpty);
    expect(field.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('the label button takes a press just above its pill', (
    tester,
  ) async {
    var presses = 0;
    await pumpTestScreen(
      tester,
      Center(
        child: LabelScanButton(
          label: tasteFitLabelButtonLabel,
          onPressed: () => presses++,
        ),
      ),
    );
    final button = tester.getRect(find.byType(LabelScanButton));
    final pill = tester.getRect(
      find.descendant(
        of: find.byType(LabelScanButton),
        matching: find.byType(Material),
      ),
    );

    // What is drawn is the 44×36 pill; the square around it is pressed.
    expect(pill.size, const Size(44, 36));
    expect(button.size, const Size(44, 44));
    await tester.tapAt(button.topCenter + const Offset(0, 1));
    await tester.tapAt(button.bottomCenter - const Offset(0, 1));
    expect(presses, 2);
    await tester.tapAt(button.center);
    expect(presses, 3);
  });

  testWidgets('the label button leaves the search field as tall as it was', (
    tester,
  ) async {
    Future<double> fieldHeight({required bool withButton}) async {
      await pumpTestScreen(
        tester,
        TasteFitSearchScreen(
          key: ValueKey<bool>(withButton),
          catalogSearchGateway: FakeCatalog(const <CatalogDrink>[]),
          labelTextRecognizer: withButton
              ? FakeLabelRecognizer(const <String>[])
              : null,
          onSelect: (_) {},
        ),
      );
      return tester.getSize(find.byType(TextFormField)).height;
    }

    expect(
      await fieldHeight(withButton: true),
      await fieldHeight(withButton: false),
    );
  });

  testWidgets('a bottle the judge names shows alone on the card; one it is '
      'sure of none for says the label was not found', (tester) async {
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: FakeBottleReader(const <BottleCut>[]),
      catalog: _JudgingCatalog(const <CatalogDrink>[
        _balvenie,
        _caution,
      ], _balvenie.id),
    );

    expect(
      find.byKey(const ValueKey<String>('label-best-candidate')),
      findsOneWidget,
    );
    expect(find.text(_balvenie.displayName), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('label-other-candidates')),
      findsNothing,
    );

    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: FakeBottleReader(const <BottleCut>[]),
      catalog: _JudgingCatalog(const <CatalogDrink>[_balvenie, _caution], null),
    );

    expect(find.text(tasteFitLabelNoMatchHint), findsOneWidget);
    expect(find.text(_balvenie.displayName), findsNothing);
  });

  testWidgets('a label nobody in the catalog matches says so', (tester) async {
    await _scanLabel(tester, lines: const <String>['동네 양조장 막걸리']);

    expect(find.text(tasteFitLabelNoMatchHint), findsOneWidget);
    // What the photo was read as stays out of the message.
    expect(find.textContaining('동네 양조장'), findsNothing);
    expect(find.text('일치하는 술이 없어요. 다른 이름으로 검색해 보세요.'), findsNothing);

    await tester.tap(find.byTooltip('입력 내용 삭제'));
    await tester.pump();
    expect(find.text('찾으시는 술의 이름을 검색해 보세요.'), findsOneWidget);
  });

  testWidgets('a back label that names nothing found asks for the front', (
    tester,
  ) async {
    // Words found on the back, a line or two the catalog does not know,
    // and no product name.
    await _scanLabel(
      tester,
      lines: const <String>[
        '식품유형: 탁주',
        '원재료명: 정제수, 쌀, 누룩',
        '동네 양조장',
        '반품 및 교환: 구입처',
      ],
    );

    expect(find.text(tasteFitLabelBackSideHint), findsOneWidget);
    expect(find.textContaining(tasteFitLabelNoMatchHint), findsNothing);
  });

  testWidgets('a back label with nothing to search asks for the front', (
    tester,
  ) async {
    await _scanLabel(
      tester,
      lines: const <String>['식품유형: 탁주', '원재료명: 정제수, 쌀', '750ml'],
    );

    expect(find.text(tasteFitLabelBackSideHint), findsOneWidget);
    expect(find.text(tasteFitLabelUnreadableHint), findsNothing);
  });

  testWidgets('drinks that are only like what was typed are said to be so', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(
          CatalogMatches(const <CatalogDrink>[_balvenie], guesses: true),
        ),
        onSelect: (_) {},
      ),
    );
    await tester.enterText(find.byType(TextField), '발배니');
    await tester.pumpAndSettle();

    expect(find.text('입력하신 이름과 비슷한 술이에요.'), findsOneWidget);
    expect(find.text(_balvenie.displayName), findsOneWidget);
  });

  testWidgets('a drink the catalog does not carry is said to be so', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(
          CatalogMatches(const <CatalogDrink>[], notCarried: 'beer'),
        ),
        onSelect: (_) {},
      ),
    );
    await tester.enterText(find.byType(TextField), '카스');
    await tester.pumpAndSettle();

    expect(
      find.text('술결은 와인, 위스키, 사케, 전통주를 다뤄요. 맥주는 다루지 않아요.'),
      findsOneWidget,
    );
    expect(find.text('일치하는 술이 없어요. 다른 이름으로 검색해 보세요.'), findsNothing);
  });

  testWidgets('an unreadable label asks for another photo', (tester) async {
    await _scanLabel(tester, lines: const <String>['40%', '750ml']);

    expect(find.text(tasteFitLabelUnreadableHint), findsOneWidget);
    expect(find.text('찾으시는 술의 이름을 검색해 보세요.'), findsOneWidget);
  });

  testWidgets(
    'opened from the home camera button it asks for the photo first',
    (tester) async {
      final recognizer = FakeLabelRecognizer(_balvenieLabel);
      await pumpTestScreen(
        tester,
        TasteFitSearchScreen(
          catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
          labelTextRecognizer: recognizer,
          pickLabelPhoto: () async => XFile(labelPhotoPath),
          scanLabelOnOpen: true,
          onSelect: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(recognizer.paths, <String>[labelPhotoPath]);
      expect(find.text(_balvenie.displayName), findsOneWidget);
    },
  );

  testWidgets(
    'opened from the home camera button, closing the camera leaves the search',
    (tester) async {
      var left = 0;
      await pumpTestScreen(
        tester,
        TasteFitSearchScreen(
          catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
          labelTextRecognizer: FakeLabelRecognizer(const <String>['X']),
          scanLabelOnOpen: true,
          onCloseOpeningScan: () => left++,
          onSelect: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      // The real camera screen; the test has no camera, so it explains that.
      await tester.tap(
        find.byKey(const ValueKey<String>('label-camera-close')),
      );
      await tester.pumpAndSettle();
      expect(left, 1);

      // The label button inside the search is an ordinary scan: closing it
      // stays.
      await tester.tap(
        find.byKey(const ValueKey<String>('taste-fit-label-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('label-camera-close')),
      );
      await tester.pumpAndSettle();
      expect(left, 1);
    },
  );

  testWidgets(
    'opened from the home camera button, an album left without a photo leaves '
    'the search too',
    (tester) async {
      // The test's phone has no album: the picker's call to it, like every
      // platform call nothing answers here, fails at once.
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.allMessagesHandler = (_, handler, message) async =>
          handler == null ? null : await handler(message);
      addTearDown(() => messenger.allMessagesHandler = null);
      var left = 0;
      await pumpTestScreen(
        tester,
        TasteFitSearchScreen(
          catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
          labelTextRecognizer: FakeLabelRecognizer(const <String>['X']),
          scanLabelOnOpen: true,
          onCloseOpeningScan: () => left++,
          onSelect: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('label-camera-album')),
      );
      await tester.pumpAndSettle();
      expect(left, 1);

      // From the label button inside the search, the reader stays.
      await tester.tap(
        find.byKey(const ValueKey<String>('taste-fit-label-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('label-camera-album')),
      );
      await tester.pumpAndSettle();
      expect(left, 1);
    },
  );

  testWidgets('retrying a label search the server failed searches the same '
      'lines again without the camera', (tester) async {
    final catalog = FlakyCatalog(const <CatalogDrink>[_balvenie]);
    final recognizer = FakeLabelRecognizer(_balvenieLabel);
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: recognizer,
      catalog: catalog,
    );
    expect(find.text('검색 서버 연결이 원활하지 않아요.'), findsOneWidget);
    final failedQueries = List<String>.of(catalog.queries);
    expect(failedQueries, isNotEmpty);

    catalog.failing = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(recognizer.paths, <String>[labelPhotoPath]);
    expect(catalog.queries.skip(failedQueries.length), failedQueries);
    expect(find.text('검색 서버 연결이 원활하지 않아요.'), findsNothing);
    expect(find.text(_balvenie.displayName), findsOneWidget);
  });

  testWidgets('retrying a typed search the server failed searches it again', (
    tester,
  ) async {
    final catalog = FlakyCatalog(const <CatalogDrink>[_balvenie]);
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(catalogSearchGateway: catalog, onSelect: (_) {}),
    );
    await typeSearch(tester, '발베니');
    await tester.pumpAndSettle();
    expect(find.text('검색 서버 연결이 원활하지 않아요.'), findsOneWidget);

    catalog.failing = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(catalog.queries, <String>['발베니', '발베니']);
    expect(find.text(_balvenie.displayName), findsOneWidget);
  });

  testWidgets('typing while a label is read stops the reading', (tester) async {
    final reading = Completer<List<String>>();
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        labelTextRecognizer: _SlowRecognizer(reading.future),
        pickLabelPhoto: () async => XFile(labelPhotoPath),
        onSelect: (_) {},
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('taste-fit-label-button')),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text(tasteFitLabelReadingHint), findsOneWidget);

    await typeSearch(tester, '발베니');
    expect(find.text(tasteFitLabelReadingHint), findsNothing);
    expect(find.text(_balvenie.displayName), findsOneWidget);
    final button = tester.widget<LabelScanButton>(
      find.byKey(const ValueKey<String>('taste-fit-label-button')),
    );
    expect(button.onPressed, isNotNull);

    // The late reading is dropped.
    reading.complete(_balvenieLabel);
    await tester.pumpAndSettle();
    expect(find.text('찾으시는 술이 맞나요?'), findsNothing);
  });

  testWidgets('typing on keeps the rows and badges until the new results', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        tasteFitGateway: FakeTasteFit(
          TasteFitResponse(
            hasCards: true,
            verdicts: <String, TasteFitVerdict>{
              _balvenie.id: _verdict(_balvenie.id, TasteFitBadge.star),
            },
          ),
        ),
        onSelect: (_) {},
      ),
    );
    await typeSearch(tester, '발베니');
    expect(find.text(_balvenie.displayName), findsOneWidget);
    expect(_badge('취향 저격'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '발베니 12');
    await tester.pump();
    expect(find.text(_balvenie.displayName), findsOneWidget);
    expect(_badge('취향 저격'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    final recognizer = FakeLabelRecognizer(_balvenieLabel);
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: recognizer,
      cancelPicker: true,
    );

    expect(recognizer.paths, isEmpty);
    expect(find.text('찾으시는 술의 이름을 검색해 보세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Two bottles side by side, each name read whole.
List<ReadLine> _twoBottles() => <ReadLine>[
  for (final (left, name, age) in <(double, String, String)>[
    (0.05, '아드벡', '10년'),
    (0.60, '글렌피딕', '12년'),
  ]) ...<ReadLine>[
    ReadLine(text: name, left: left, top: 0.30, width: 0.3, height: 0.06),
    ReadLine(text: age, left: left + 0.1, top: 0.38, width: 0.1, height: 0.03),
  ],
];

class _SlowRecognizer implements LabelTextRecognizer {
  _SlowRecognizer(this.lines);

  final Future<List<String>> lines;

  @override
  Future<List<ReadLine>> recognizeLines(String imagePath) =>
      lines.then(labelLines);
}

Future<void> _scanLabel(
  WidgetTester tester, {
  required List<String> lines,
  bool cancelPicker = false,
  LabelTextRecognizer? recognizer,
  CatalogSearchGateway? catalog,
  TasteFitGateway? fit,
}) async {
  await pumpTestScreen(
    tester,
    TasteFitSearchScreen(
      catalogSearchGateway: catalog ?? FakeCatalog(const <CatalogDrink>[]),
      tasteFitGateway: fit,
      labelTextRecognizer: recognizer ?? FakeLabelRecognizer(lines),
      pickLabelPhoto: () async => cancelPicker ? null : XFile(labelPhotoPath),
      onSelect: (_) {},
    ),
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('taste-fit-label-button')),
  );
  await tester.pumpAndSettle();
}

/// Finds [results] for every label and judges the bottle's photo to be
/// [drinkId], or none of them when `null`.
class _JudgingCatalog extends FakeCatalog implements LabelPhotoJudge {
  _JudgingCatalog(super.results, this.drinkId);

  final String? drinkId;

  @override
  Future<String?> pickByPhoto(
    Uint8List photo,
    List<String> candidateIds, {
    required bool appSure,
  }) async => drinkId;
}

class _SlowFitGateway implements TasteFitGateway {
  @override
  Future<TasteFitResponse> judge(List<String> productIds) =>
      Completer<TasteFitResponse>().future;
}

/// Answers each call only when the test completes its completer.
class _GatedFitGateway implements TasteFitGateway {
  final calls = <Completer<TasteFitResponse>>[];

  @override
  Future<TasteFitResponse> judge(List<String> productIds) {
    final call = Completer<TasteFitResponse>();
    calls.add(call);
    return call.future;
  }
}

/// Answers every fit call with [response], which the test may change, and
/// keeps the product ids asked.
class _ChangingFit implements TasteFitGateway {
  _ChangingFit(this.response);

  TasteFitResponse response;
  final List<List<String>> requests = <List<String>>[];

  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    requests.add(productIds);
    return response;
  }
}

/// Answers each search with [results] only when the test completes its call.
class _GatedCatalog with SearchManyByOne {
  _GatedCatalog(this.results);

  final List<CatalogDrink> results;
  final calls = <Completer<void>>[];

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final call = Completer<void>();
    calls.add(call);
    await call.future;
    return results;
  }
}

class _FailingFitGateway implements TasteFitGateway {
  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    throw const TasteFitGatewayException();
  }
}

/// A catalog with the label word search: the line search answers [results]
/// and the word search [candidates], or fails when they are `null`.
class _WordCatalog extends FakeCatalog implements LabelWordSearch {
  _WordCatalog(super.results, this.candidates);

  final List<LabelCandidate>? candidates;
  List<String> words = const <String>[];

  @override
  Future<List<LabelCandidate>> searchByLabelWords(
    List<String> words, {
    List<String> alsoIds = const <String>[],
  }) async {
    this.words = words;
    final answer = candidates;
    if (answer == null) throw const CatalogSearchException();
    return answer;
  }
}

LabelCandidate _wordCandidate(CatalogDrink drink) => LabelCandidate(
  drink: drink,
  kind: 'whisky',
  nameRarity: <String, double>{
    for (final word in labelMatchWords(
      '${drink.nameEn ?? ''} ${drink.displayName}',
    ))
      word: 8,
  },
  found: 8,
);

/// Answers a search with the drink whose name it holds.
class _ByNameCatalog with SearchManyByOne {
  _ByNameCatalog(this.drinks);

  final Map<String, CatalogDrink> drinks;

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async => <CatalogDrink>[
    for (final MapEntry(:key, :value) in drinks.entries)
      if (query.contains(key)) value,
  ];
}
