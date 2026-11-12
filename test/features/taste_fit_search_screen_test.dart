import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/suggested_drinks.dart';
import 'package:soolgyul/src/features/recording/presentation/widgets/selected_drink_card.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_text_recognizer.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/label_scan_button.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_badge.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';

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

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextFormField), query);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
  await tester.pump();
}

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

    await _search(tester, '발베니');

    expect(catalog.queries, <String>['발베니']);
    expect(fit.requests, <List<String>>[
      <String>[_balvenie.id, _caution.id, _neutral.id, _noInfo.id],
    ]);
    expect(find.text('발베니 12년 더블우드'), findsOneWidget);
    expect(_badge('취향 저격'), findsOneWidget);
    expect(_badge('낯설 수 있어요'), findsOneWidget);
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

    await _search(tester, '발베니');
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

    await _search(tester, '발베니');

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

    await _search(tester, '발베니');

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

    await _search(tester, '발베니');
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
    await _search(tester, '없는 술');
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
    await _search(tester, '아드벡');
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
    expect(_badge('취향 저격'), findsNothing);

    await tester.tap(find.text(_balvenie.displayName));
    expect(picked?.verdict, isNull);
    expect(picked?.judged, isFalse);
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

    expect(recognizer.paths, <String>[_labelPhotoPath]);
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
    await _search(tester, '아드벡');
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
        ]),
        pickLabelPhoto: () async => XFile(_labelPhotoPath),
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

    await tester.tap(best);
    expect(picked?.drink.id, _balvenie.id);
  });

  testWidgets('a label nobody in the catalog matches says so', (tester) async {
    await _scanLabel(tester, lines: const <String>['동네 양조장 막걸리']);

    expect(find.text(tasteFitLabelNoMatchHint), findsOneWidget);
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
    expect(find.text(tasteFitLabelNoMatchHint), findsNothing);
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
      final recognizer = FakeLabelRecognizer(const <String>['THE BALVENIE']);
      await pumpTestScreen(
        tester,
        TasteFitSearchScreen(
          catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
          labelTextRecognizer: recognizer,
          pickLabelPhoto: () async => XFile(_labelPhotoPath),
          scanLabelOnOpen: true,
          onSelect: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(recognizer.paths, <String>[_labelPhotoPath]);
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

  testWidgets('typing while a label is read stops the reading', (tester) async {
    final reading = Completer<List<String>>();
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_balvenie]),
        labelTextRecognizer: _SlowRecognizer(reading.future),
        pickLabelPhoto: () async => XFile(_labelPhotoPath),
        onSelect: (_) {},
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('taste-fit-label-button')),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text(tasteFitLabelReadingHint), findsOneWidget);

    await _search(tester, '발베니');
    expect(find.text(tasteFitLabelReadingHint), findsNothing);
    expect(find.text(_balvenie.displayName), findsOneWidget);
    final button = tester.widget<LabelScanButton>(
      find.byKey(const ValueKey<String>('taste-fit-label-button')),
    );
    expect(button.onPressed, isNotNull);

    // The late reading is dropped.
    reading.complete(const <String>['THE BALVENIE']);
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
    await _search(tester, '발베니');
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
    final recognizer = FakeLabelRecognizer(const <String>['THE BALVENIE']);
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

class _SlowRecognizer implements LabelTextRecognizer {
  _SlowRecognizer(this.lines);

  final Future<List<String>> lines;

  @override
  Future<List<String>> recognizeLines(String imagePath) => lines;
}

Future<void> _scanLabel(
  WidgetTester tester, {
  required List<String> lines,
  bool cancelPicker = false,
  FakeLabelRecognizer? recognizer,
  CatalogSearchGateway? catalog,
  TasteFitGateway? fit,
}) async {
  await pumpTestScreen(
    tester,
    TasteFitSearchScreen(
      catalogSearchGateway: catalog ?? FakeCatalog(const <CatalogDrink>[]),
      tasteFitGateway: fit,
      labelTextRecognizer: recognizer ?? FakeLabelRecognizer(lines),
      pickLabelPhoto: () async => cancelPicker ? null : XFile(_labelPhotoPath),
      onSelect: (_) {},
    ),
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('taste-fit-label-button')),
  );
  await tester.pumpAndSettle();
}

const String _labelPhotoPath = '/photos/label.jpg';

class _SlowFitGateway implements TasteFitGateway {
  @override
  Future<TasteFitResponse> judge(List<String> productIds) =>
      Completer<TasteFitResponse>().future;
}

class _FailingFitGateway implements TasteFitGateway {
  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    throw const TasteFitGatewayException();
  }
}
