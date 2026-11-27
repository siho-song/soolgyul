import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/suggested_drinks.dart';
import 'package:soolgyul/src/features/recording/presentation/widgets/selected_drink_card.dart';
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
