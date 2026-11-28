import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';

// 취향 → 기록 검색 → a record's card → back to the search as it was.

class _Letters implements TasteLettersGateway {
  @override
  Future<TasteLettersSnapshot> load() async => const TasteLettersSnapshot(
    state: TasteLettersState(axes: {}, recordCount: 2),
  );
}

class _History implements PreferenceHistoryGateway {
  int allLoads = 0;

  @override
  Future<List<HistoryRecord>> loadAll() async {
    allLoads++;
    return <HistoryRecord>[
      HistoryRecord(
        resultId: 'card-whisky',
        title: '라프로익 10',
        categoryKey: 'whisky',
        categoryLabel: '위스키',
        recordedAt: DateTime(2026, 11, 3, 21),
      ),
      HistoryRecord(
        resultId: 'card-wine',
        title: '샤토 테스트',
        categoryKey: 'wine',
        categoryLabel: '와인',
        recordedAt: DateTime(2026, 6, 18, 20),
      ),
    ];
  }

  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async =>
      const <HistoryRecord>[];

  @override
  Future<DateTime?> latestRecordedAt() async => null;
}

class _Cards implements TasteCardGateway {
  final opened = <String>[];

  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) async {
    opened.add(resultId);
    return TasteCardResult(
      resultId: resultId,
      recordId: '30000000-0000-4000-8000-000000000009',
      snapshotRef: designTasteCard.snapshotRef,
      ownership: TasteCardOwnership.saved,
      viewData: designTasteCard,
    );
  }

  @override
  Future<void> deleteOwnedResult(String resultId) async {}

  @override
  Future<TasteCardCreateOutcome> create(CreateTasteCardResultRequest r) =>
      throw UnimplementedError();

  @override
  Future<TasteCardResult> convert(AnonymousTasteCardConversionRequest r) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('the chip opens the search, a row opens its card, and the way '
      'back from the card keeps what was typed and listed', (tester) async {
    useTestViewport(tester);
    openAppAtDebugRoute(AppRoute.preference);
    final history = _History();
    final cards = _Cards();
    await tester.pumpWidget(
      App(
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        tasteLettersGateway: _Letters(),
        preferenceHistoryGateway: history,
        cardCountLoader: () async => 2,
        tasteCardGateway: cards,
      ),
    );
    await tester.pumpAndSettle();
    expect(history.allLoads, 0, reason: 'only the search asks for all');

    await tester.tap(find.byKey(const ValueKey<String>('history-search-chip')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey<String>('history-search-field'));
    final list = find.byKey(const ValueKey<String>('history-search-list'));
    expect(field, findsOneWidget);
    // Its own header, and no tab bar under it.
    expect(find.text('기록 검색'), findsOneWidget);
    expect(find.byTooltip('이전 화면으로 이동'), findsOneWidget);
    expect(find.text('내 정보'), findsNothing);
    expect(find.text('라프로익 10'), findsOneWidget);
    expect(find.text('샤토 테스트'), findsOneWidget);

    await tester.enterText(field, '샤토');
    await tester.pumpAndSettle();
    expect(find.text('라프로익 10'), findsNothing);
    await tester.tap(find.text('와인 · 2026.06.18'));
    await tester.pumpAndSettle();
    expect(cards.opened, ['card-wine']);
    expect(find.byType(TasteCardScreen), findsOneWidget);

    // Back from the card: the search as it was left.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TasteCardScreen), findsNothing);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '샤토',
    );
    expect(
      find.descendant(of: list, matching: find.text('샤토 테스트')),
      findsOneWidget,
    );
    expect(find.text('라프로익 10'), findsNothing);
    expect(history.allLoads, 1, reason: 'nothing changed, nothing asked again');

    // Back again: the 취향 tab.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(
      find.byKey(const ValueKey<String>('history-search-chip')),
      findsOneWidget,
    );
    expect(find.text('내 정보'), findsOneWidget);
  });
}
