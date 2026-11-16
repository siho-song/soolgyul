import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';
import '../support/test_catalog.dart';

/// Answers each request only when the test completes it.
class _SlowCards implements TasteCardGateway {
  final requests = <CreateTasteCardResultRequest>[];
  final answers = <Completer<TasteCardCreateOutcome>>[];

  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardCreateOutcome> create(CreateTasteCardResultRequest request) {
    requests.add(request);
    answers.add(Completer<TasteCardCreateOutcome>());
    return answers.last.future;
  }

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteOwnedResult(String resultId) async {}

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequest request,
  ) => throw UnimplementedError();
}

final _back = find.byTooltip('이전 화면으로 이동');

void main() {
  testWidgets('a card being made cannot be left; one that failed leads back '
      'to its questions, and the same answers send the same record again', (
    tester,
  ) async {
    addTearDown(captureErrorReports((_, _, _) {}));
    final cards = _SlowCards();
    await pumpAppAtRecordEntry(tester, cards);
    await tester.enterText(find.byType(TextField), '테스트 드라이');
    await pumpCatalogSearch(tester);
    await tester.tap(find.text('테스트 드라이 화이트 와인'));
    await tester.pump();
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tapSensoryOption(tester, 'revisit:wantAgain');
    await tapSensoryOption(tester, 'sensory-next');
    await tapSensoryOption(tester, 'aroma:unsure');
    await answerAllTastesLiked(tester);
    await tapSensoryOption(tester, 'mouthfeel:unsure');
    // The last question sends the record; its spinner never settles.
    await tester.tap(find.byKey(const ValueKey('finish:unsure')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('나만의 술결을 분석하고 있어요'), findsOneWidget);
    expect(cards.requests, hasLength(1));

    // No back in the header, and the phone's back does nothing.
    expect(_back, findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('나만의 술결을 분석하고 있어요'), findsOneWidget);
    expect(cards.requests, hasLength(1));

    // The request fails: the header leads back to the last question.
    cards.answers.single.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('술결 카드를 완성하지 못했어요'), findsOneWidget);
    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.byType(TasteCardStatusScreen), findsNothing);
    expect(find.byKey(const ValueKey('sensory-next')), findsOneWidget);

    // Unchanged answers go out again as the same record.
    await tapSensoryOptionNoSettle(tester);
    expect(cards.requests, hasLength(2));
    expect(
      cards.requests.last.idempotencyKey,
      cards.requests.first.idempotencyKey,
    );
    cards.answers.last.complete(
      TasteCardFinalOutcome(
        TasteCardResult(
          resultId: '20000000-0000-4000-8000-000000000001',
          recordId: '30000000-0000-4000-8000-000000000001',
          snapshotRef: designTasteCard.snapshotRef,
          ownership: TasteCardOwnership.saved,
          viewData: designTasteCard,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TasteCardScreen), findsOneWidget);
    expect(_back, findsNothing);
  });
}

/// 다음 on the last question; the waiting page's spinner never settles.
Future<void> tapSensoryOptionNoSettle(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('sensory-next')));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}
