import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/suggested_drinks.dart';
import 'package:soolgyul/src/features/recording/presentation/drink_search_screen.dart';
import 'package:soolgyul/src/features/recording/presentation/widgets/selected_drink_card.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/label_photo_flow.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_state_view.dart';

import '../support/app_test_harness.dart';
import '../support/fake_search.dart';
import '../support/test_catalog.dart';

const _drink = CatalogDrink(
  id: 'croisade-sb',
  displayName: '라 크라사드 소비뇽 블랑',
  category: DrinkCategory.whiteWine,
  styleLabel: '화이트 와인',
  abvPercent: 12,
);

void main() {
  tearDown(SuggestedDrinks.clear);

  testWidgets('prefetched suggestions show on the first frame', (tester) async {
    final gateway = FakeCatalog(const <CatalogDrink>[_drink]);
    await SuggestedDrinks.load(gateway, const <String>['라 크라사드 소비뇽 블랑']);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordDrinkSearchScreen(
            catalogSearchGateway: gateway,
            suggestedDrinkNames: const <String>['라 크라사드 소비뇽 블랑'],
            onDrinkSelection: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('많이 기록하는 술'), findsOneWidget);
    expect(find.text('라 크라사드 소비뇽 블랑'), findsOneWidget);
    expect(gateway.queries, <String>['라 크라사드 소비뇽 블랑']);
  });

  testWidgets('without a recognizer the field has no label button', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_drink]),
        onDrinkSelection: (_) {},
      ),
    );
    expect(find.text(tasteFitLabelButtonLabel), findsNothing);
  });

  testWidgets('a label photo searches its naming lines into the result list', (
    tester,
  ) async {
    final gateway = FakeCatalog(const <CatalogDrink>[_drink]);
    final recognizer = FakeLabelRecognizer(const <String>[
      'LA CROISADE',
      'Sauvignon Blanc',
      '12% vol',
    ]);
    DrinkSelection? chosen;
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: gateway,
        labelTextRecognizer: recognizer,
        pickLabelPhoto: () async => XFile('/photos/label.jpg'),
        suggestedDrinkNames: const <String>['라 크라사드 소비뇽 블랑'],
        onDrinkSelection: (selection) => chosen = selection,
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('drink-search-label-button')),
    );
    await tester.pumpAndSettle();

    expect(recognizer.paths, <String>['/photos/label.jpg']);
    expect(gateway.queries, isNotEmpty);
    expect(gateway.queries.every((q) => !q.contains('12%')), isTrue);
    // The likeliest bottle is chosen at once and asked about on the card;
    // the label's lines are not shown.
    expect(find.text('찾으시는 술이 맞나요?'), findsOneWidget);
    expect(find.textContaining('라벨에서 읽은 글자'), findsNothing);
    expect(find.text('많이 기록하는 술'), findsNothing);
    // A picked drink leaves only the clear button in the field.
    final labelButton = find.byKey(
      const ValueKey<String>('drink-search-label-button'),
    );
    expect(labelButton, findsNothing);
    expect(find.byTooltip('입력 내용 삭제'), findsOneWidget);
    await tester.tap(find.text('다음'));
    expect(chosen?.displayName, '라 크라사드 소비뇽 블랑');

    await tester.tap(find.byTooltip('입력 내용 삭제'));
    await tester.pump();
    expect(labelButton, findsOneWidget);
  });

  testWidgets('an unreadable label asks for another photo', (tester) async {
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_drink]),
        labelTextRecognizer: FakeLabelRecognizer(const <String>[
          '40%',
          '750ml',
        ]),
        pickLabelPhoto: () async => XFile('/photos/label.jpg'),
        onDrinkSelection: (_) {},
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('drink-search-label-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text(tasteFitLabelUnreadableHint), findsOneWidget);
    expect(find.text('라 크라사드 소비뇽 블랑'), findsNothing);
  });

  testWidgets('typing searches the catalog once the debounce settles', (
    tester,
  ) async {
    final gateway = FakeCatalog(const <CatalogDrink>[_drink]);
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: gateway,
        onDrinkSelection: (_) {},
      ),
    );

    await tester.enterText(find.byType(TextFormField), '크라');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextFormField), '크라사드');
    // The screen's typing debounce is an inline 250 ms constant.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(gateway.queries, <String>['크라사드']);
    expect(find.text('라 크라사드 소비뇽 블랑'), findsOneWidget);
    expect(find.text('화이트 와인 · 12%'), findsOneWidget);
    expect(find.textContaining('기록'), findsNothing);
  });

  testWidgets('the field spinner shows only while the catalog answers', (
    tester,
  ) async {
    final gateway = _PendingGateway();
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: gateway,
        onDrinkSelection: (_) {},
      ),
    );
    final spinner = find.byKey(
      const ValueKey<String>('app-text-field-loading'),
    );

    await tester.enterText(find.byType(TextFormField), '크라사드');
    await tester.pump(const Duration(milliseconds: 100));
    expect(spinner, findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 150));
    expect(spinner, findsOneWidget);

    gateway.reply.complete(const <CatalogDrink>[_drink]);
    await tester.pump();
    expect(spinner, findsNothing);
    expect(find.text('라 크라사드 소비뇽 블랑'), findsOneWidget);
  });

  testWidgets('the first search shows a spinner where the rows will come', (
    tester,
  ) async {
    final gateway = _PendingGateway();
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: gateway,
        onDrinkSelection: (_) {},
      ),
    );

    // From the first key, the typing pause included.
    await tester.enterText(find.byType(TextFormField), '크라사드');
    await tester.pump();
    expect(find.byType(AppLoadingView), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(AppLoadingView), findsOneWidget);

    gateway.reply.complete(const <CatalogDrink>[_drink]);
    await tester.pump();
    expect(find.byType(AppLoadingView), findsNothing);
    expect(find.text('라 크라사드 소비뇽 블랑'), findsOneWidget);
  });

  testWidgets('typing on keeps the rows until the new results', (tester) async {
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_drink]),
        onDrinkSelection: (_) {},
      ),
    );
    await tester.enterText(find.byType(TextFormField), '크라');
    await pumpCatalogSearch(tester);
    final row = find.text('화이트 와인 · 12%');
    expect(row, findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '크라사드');
    await tester.pump();
    expect(row, findsOneWidget);
    expect(find.byType(AppLoadingView), findsNothing);
    await pumpCatalogSearch(tester);
    expect(row, findsOneWidget);
  });

  testWidgets('tapping a suggested drink selects it and enables next', (
    tester,
  ) async {
    final selections = <DrinkSelection>[];
    final gateway = FakeCatalog(const <CatalogDrink>[_drink]);
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: gateway,
        suggestedDrinkNames: const <String>['라 크라사드 소비뇽 블랑', '없는 술'],
        onDrinkSelection: selections.add,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('많이 기록하는 술'), findsOneWidget);
    expect(find.text('라 크라사드 소비뇽 블랑'), findsOneWidget);
    expect(find.text('없는 술'), findsNothing);
    expect(_nextButton(tester).onPressed, isNull);

    await tester.tap(find.text('라 크라사드 소비뇽 블랑'));
    await tester.pumpAndSettle();

    expect(find.text('많이 기록하는 술'), findsNothing);
    expect(find.text('찾으시는 술이 맞나요?'), findsOneWidget);
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(selections.single.catalogDrink.id, _drink.id);
  });

  testWidgets('suggestions hide while a search is typed', (tester) async {
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_drink]),
        suggestedDrinkNames: const <String>['라 크라사드 소비뇽 블랑'],
        onDrinkSelection: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('많이 기록하는 술'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '크라');
    await tester.pump();
    expect(find.text('많이 기록하는 술'), findsNothing);
  });

  testWidgets('a search without a match says so and offers nothing else', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[]),
        onDrinkSelection: (_) {},
      ),
    );

    await tester.enterText(find.byType(TextFormField), '없는 술');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.text('일치하는 술이 없어요. 다른 이름으로 검색해 보세요.'), findsOneWidget);
    expect(find.textContaining('기록'), findsNothing);
  });

  testWidgets('scrolling the results to the end loads the next page', (
    tester,
  ) async {
    final gateway = PagedFakeCatalog(<CatalogDrink>[
      for (var n = 1; n <= 25; n++)
        CatalogDrink(
          id: 'drink-$n',
          displayName: '발베니 $n',
          category: DrinkCategory.whisky,
        ),
    ]);
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: gateway,
        onDrinkSelection: (_) {},
      ),
    );

    await tester.enterText(find.byType(TextFormField), '발베니');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(gateway.offsets, <int>[0]);

    await tester.dragUntilVisible(
      find.text('발베니 25'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(gateway.offsets, <int>[0, 20]);
  });

  testWidgets('a chosen catalog product is shown for confirmation', (
    tester,
  ) async {
    const drink = CatalogDrink(
      id: 'croisade-sb',
      displayName: '라 크라사드 소비뇽 블랑',
      nameEn: 'La Croisade Sauvignon Blanc',
      category: DrinkCategory.whiteWine,
      styleLabel: '화이트 와인',
      abvPercent: 11.5,
      countryCode: 'FR',
      region: '랑그독 루씨용',
    );
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogDrinks: const <CatalogDrink>[drink],
        onDrinkSelected: (_) {},
      ),
    );

    await tester.enterText(find.byType(TextFormField), '크라사드');
    await tester.pump();
    expect(find.text('찾으시는 술이 맞나요?'), findsNothing);
    expect(find.text('화이트 와인 · 11.5%'), findsOneWidget);
    expect(find.textContaining('기록'), findsNothing);

    await tester.tap(find.text('라 크라사드 소비뇽 블랑'));
    await tester.pumpAndSettle();
    expect(find.text('찾으시는 술이 맞나요?'), findsOneWidget);
    expect(find.text('La Croisade Sauvignon Blanc'), findsOneWidget);
    expect(find.text('화이트 와인 · 프랑스 랑그독 루씨용 · 11.5%'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.enterText(find.byType(TextFormField), '크라사드 소');
    await tester.pump();
    expect(find.text('찾으시는 술이 맞나요?'), findsNothing);
  });

  testWidgets('selecting a result shows the card and clearing resets it', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogDrinks: const <CatalogDrink>[_drink],
        onDrinkSelection: (_) {},
      ),
    );

    await tester.enterText(find.byType(TextFormField), '크라사드');
    await tester.pump();
    await tester.tap(find.text('라 크라사드 소비뇽 블랑'));
    await tester.pumpAndSettle();
    expect(find.text('찾으시는 술이 맞나요?'), findsOneWidget);
    expect(_nextButton(tester).onPressed, isNotNull);

    await tester.tap(find.byTooltip('입력 내용 삭제'));
    await tester.pumpAndSettle();

    expect(find.text('찾으시는 술이 맞나요?'), findsNothing);
    expect(find.text('라 크라사드 소비뇽 블랑'), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      isEmpty,
    );
    expect(_nextButton(tester).onPressed, isNull);
  });

  testWidgets('a failed catalog search shows a notice and no results', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FailingCatalog(),
        onDrinkSelection: (_) {},
      ),
    );

    await tester.enterText(find.byType(TextFormField), '막걸리');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.text('검색 서버 연결이 원활하지 않아요.'), findsOneWidget);
    expect(find.textContaining('기록'), findsNothing);
    expect(find.text('일치하는 술이 없어요. 다른 이름으로 검색해 보세요.'), findsNothing);
  });

  testWidgets('a whisky whose name holds 하이볼 is found like any other', (
    tester,
  ) async {
    const smokehead = CatalogDrink(
      id: 'smokehead-high-voltage',
      displayName: '스모크 헤드 하이볼티지',
      category: DrinkCategory.whisky,
    );
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogDrinks: const <CatalogDrink>[smokehead],
        onDrinkSelection: (_) {},
      ),
    );

    await tester.enterText(find.byType(TextFormField), '하이볼');
    await tester.pump();

    expect(find.text('스모크 헤드 하이볼티지'), findsOneWidget);
  });

  testWidgets('a label chooses its likeliest bottle; another can be picked', (
    tester,
  ) async {
    const other = CatalogDrink(
      id: 'croisade-rose',
      displayName: '라 크라사드 로제',
      category: DrinkCategory.redWine,
    );
    DrinkSelection? chosen;
    await pumpTestScreen(
      tester,
      RecordDrinkSearchScreen(
        catalogSearchGateway: FakeCatalog(const <CatalogDrink>[_drink, other]),
        labelTextRecognizer: FakeLabelRecognizer(const <String>['LA CROISADE']),
        pickLabelPhoto: () async => XFile('/photos/label.jpg'),
        onDrinkSelection: (selection) => chosen = selection,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('drink-search-label-button')),
    );
    await tester.pumpAndSettle();

    final others = find.byKey(const ValueKey<String>('label-other-candidates'));
    expect(find.text('찾으시는 술이 맞나요?'), findsOneWidget);
    expect(find.text(otherCandidatesTitle), findsOneWidget);
    expect(
      find.descendant(of: others, matching: find.text(other.displayName)),
      findsOneWidget,
    );
    expect(_nextButton(tester).onPressed, isNotNull);

    await tester.tap(
      find.descendant(of: others, matching: find.text(other.displayName)),
    );
    await tester.pump();
    expect(
      find.descendant(of: others, matching: find.text(_drink.displayName)),
      findsOneWidget,
    );
    await tester.tap(find.text('다음'));
    expect(chosen?.catalogId, other.id);
  });
}

AppButton _nextButton(WidgetTester tester) {
  return tester.widget<AppButton>(
    find.ancestor(of: find.text('다음'), matching: find.byType(AppButton)),
  );
}

class _PendingGateway with SearchManyByOne {
  final reply = Completer<List<CatalogDrink>>();

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) => reply.future;
}
