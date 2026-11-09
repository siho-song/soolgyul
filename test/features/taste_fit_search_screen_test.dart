import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/suggested_drinks.dart';
import 'package:soolgyul/src/features/taste_fit/data/label_text_recognizer.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/label_scan_button.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_badge.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';

import '../support/app_test_harness.dart';

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
    final fit = _FitGateway(
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
    final catalog = _Catalog(const <CatalogDrink>[
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
    expect(find.text('잘 맞아요'), findsOneWidget);
    expect(find.text('조심'), findsOneWidget);
    expect(find.text('무난해요'), findsOneWidget);
    expect(find.byType(TasteFitRowBadge), findsNWidgets(4));
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == AppIconAsset.heartFull,
      ),
      findsOneWidget,
    );
    // Full, empty and half hearts for the three verdicts; no heart for no_info.
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == AppIconAsset.heartEmpty,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == AppIconAsset.heartHalf,
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
    final catalog = _PagedCatalog(drinks);
    final fit = _FitGateway(
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
        catalogSearchGateway: _Catalog(const <CatalogDrink>[_balvenie]),
        tasteFitGateway: _FitGateway(
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
    expect(find.text('잘 맞아요'), findsNothing);
  });

  testWidgets('a failed fit call still lists the results', (tester) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: _Catalog(const <CatalogDrink>[_balvenie]),
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
        catalogSearchGateway: _Catalog(const <CatalogDrink>[_balvenie]),
        tasteFitGateway: _FitGateway(
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
        catalogSearchGateway: _Catalog(const <CatalogDrink>[]),
        onSelect: (_) {},
      ),
    );

    expect(find.text('술 이름을 검색해보세요'), findsOneWidget);
    await _search(tester, '없는 술');
    expect(find.text('검색 결과가 없어요. 다른 이름으로 찾아보세요.'), findsOneWidget);

    await tester.tap(find.byTooltip('검색어 지우기'));
    await tester.pump();
    expect(find.text('술 이름을 검색해보세요'), findsOneWidget);
  });

  testWidgets('suggested drinks show with their badges before any search', (
    tester,
  ) async {
    addTearDown(SuggestedDrinks.clear);
    final catalog = _Catalog(const <CatalogDrink>[_balvenie]);
    final fit = _FitGateway(
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
    expect(find.text('잘 맞아요'), findsOneWidget);
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
    await tester.tap(find.byTooltip('검색어 지우기'));
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
        catalogSearchGateway: _Catalog(const <CatalogDrink>[_balvenie]),
        tasteFitGateway: _SlowFitGateway(),
        suggestedDrinkNames: <String>[_balvenie.displayName],
        onSelect: (selection) => picked = selection,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('잘 맞아요'), findsNothing);

    await tester.tap(find.text(_balvenie.displayName));
    expect(picked?.verdict, isNull);
    expect(picked?.judged, isFalse);
  });

  testWidgets('without a recognizer there is no label button', (tester) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: _Catalog(const <CatalogDrink>[]),
        onSelect: (_) {},
      ),
    );
    expect(find.text(tasteFitLabelButtonLabel), findsNothing);
  });

  testWidgets('a label photo searches its naming lines and badges the rows', (
    tester,
  ) async {
    final catalog = _Catalog(const <CatalogDrink>[_balvenie]);
    final fit = _FitGateway(
      TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{
          _balvenie.id: _verdict(_balvenie.id, TasteFitBadge.star),
        },
      ),
    );
    final recognizer = _Recognizer(const <String>[
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
    expect(catalog.queries, <String>['BALVENIE', 'DoubleWood']);
    expect(find.text('라벨에서 읽은 글자: BALVENIE · DoubleWood'), findsOneWidget);
    expect(find.text('발베니 12년 더블우드'), findsOneWidget);
    expect(find.text('잘 맞아요'), findsOneWidget);
    expect(fit.requests, <List<String>>[
      <String>[_balvenie.id],
    ]);

    // Typing again leaves the label behind.
    await _search(tester, '아드벡');
    expect(find.textContaining('라벨에서 읽은 글자'), findsNothing);
  });

  testWidgets('a label nobody in the catalog matches says so', (tester) async {
    await _scanLabel(tester, lines: const <String>['동네 양조장 막걸리']);

    expect(find.text(tasteFitLabelNoMatchHint), findsOneWidget);
    expect(find.text('검색 결과가 없어요. 다른 이름으로 찾아보세요.'), findsNothing);

    await tester.tap(find.byTooltip('검색어 지우기'));
    await tester.pump();
    expect(find.text('술 이름을 검색해보세요'), findsOneWidget);
  });

  testWidgets('an unreadable label asks for another photo', (tester) async {
    await _scanLabel(tester, lines: const <String>['40%', '750ml']);

    expect(find.text(tasteFitLabelUnreadableHint), findsOneWidget);
    expect(find.text('술 이름을 검색해보세요'), findsOneWidget);
  });

  testWidgets(
    'opened from the home camera button it asks for the photo first',
    (tester) async {
      final recognizer = _Recognizer(const <String>['THE BALVENIE']);
      await pumpTestScreen(
        tester,
        TasteFitSearchScreen(
          catalogSearchGateway: _Catalog(const <CatalogDrink>[_balvenie]),
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

  testWidgets('typing while a label is read stops the reading', (tester) async {
    final reading = Completer<List<String>>();
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: _Catalog(const <CatalogDrink>[_balvenie]),
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
    expect(find.textContaining('라벨에서 읽은 글자'), findsNothing);
  });

  testWidgets('typing on keeps the rows and badges until the new results', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitSearchScreen(
        catalogSearchGateway: _Catalog(const <CatalogDrink>[_balvenie]),
        tasteFitGateway: _FitGateway(
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
    expect(find.text('잘 맞아요'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '발베니 12');
    await tester.pump();
    expect(find.text(_balvenie.displayName), findsOneWidget);
    expect(find.text('잘 맞아요'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    final recognizer = _Recognizer(const <String>['THE BALVENIE']);
    await _scanLabel(
      tester,
      lines: const <String>[],
      recognizer: recognizer,
      cancelPicker: true,
    );

    expect(recognizer.paths, isEmpty);
    expect(find.text('술 이름을 검색해보세요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SlowRecognizer implements LabelTextRecognizer {
  _SlowRecognizer(this.lines);

  final Future<List<String>> lines;

  @override
  Future<List<String>> recognizeLines(String imagePath) => lines;
}

class _Recognizer implements LabelTextRecognizer {
  _Recognizer(this.lines);

  final List<String> lines;
  final List<String> paths = <String>[];

  @override
  Future<List<String>> recognizeLines(String imagePath) async {
    paths.add(imagePath);
    return lines;
  }
}

Future<void> _scanLabel(
  WidgetTester tester, {
  required List<String> lines,
  bool cancelPicker = false,
  _Recognizer? recognizer,
  CatalogSearchGateway? catalog,
  TasteFitGateway? fit,
}) async {
  await pumpTestScreen(
    tester,
    TasteFitSearchScreen(
      catalogSearchGateway: catalog ?? _Catalog(const <CatalogDrink>[]),
      tasteFitGateway: fit,
      labelTextRecognizer: recognizer ?? _Recognizer(lines),
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

class _Catalog implements CatalogSearchGateway {
  _Catalog(this.results);

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

class _SlowFitGateway implements TasteFitGateway {
  @override
  Future<TasteFitResponse> judge(List<String> productIds) =>
      Completer<TasteFitResponse>().future;
}

class _FitGateway implements TasteFitGateway {
  _FitGateway(this.response);

  final TasteFitResponse response;
  final List<List<String>> requests = <List<String>>[];

  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    requests.add(productIds);
    return response;
  }
}

class _FailingFitGateway implements TasteFitGateway {
  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    throw const TasteFitGatewayException();
  }
}

class _PagedCatalog implements CatalogSearchGateway {
  _PagedCatalog(this.all);

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
