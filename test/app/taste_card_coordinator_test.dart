import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/flows/app_gateways.dart';
import 'package:soolgyul/src/app/flows/flow_host.dart';
import 'package:soolgyul/src/app/flows/taste_card_coordinator.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';

class _Host implements FlowHost {
  _Host(this.router);

  @override
  final AppRouter router;

  @override
  bool get mounted => true;

  @override
  BuildContext get context => throw UnimplementedError();

  @override
  void refresh(VoidCallback update) => update();

  @override
  void showFeedback(String message, {bool success = false}) {}

  @override
  void back() => router.pop();
}

/// Answers each request only when the test completes it.
class _Cards implements TasteCardGateway {
  final requests = <CreateTasteCardResultRequest>[];
  final answers = <Completer<TasteCardCreateOutcome>>[];
  final opened = Completer<TasteCardResult>();

  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardCreateOutcome> create(CreateTasteCardResultRequest request) {
    requests.add(request);
    answers.add(Completer<TasteCardCreateOutcome>());
    return answers.last.future;
  }

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) => opened.future;

  @override
  Future<void> deleteOwnedResult(String resultId) async {}

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequest request,
  ) => throw UnimplementedError();
}

CreateTasteCardResultRequest _request({
  required String idempotencyKey,
  String? anonymousSessionId,
}) => CreateTasteCardResultRequest(
  idempotencyKey: idempotencyKey,
  questionnaireVersion: 'test',
  alcoholIdentification: const AlcoholIdentificationInput.catalogMatch(
    alcoholItemId: 'drink',
    alcoholNameSnapshot: '테스트 와인',
  ),
  answers: const <QuestionnaireAnswerInput>[],
);

final _card = TasteCardResult(
  resultId: '20000000-0000-4000-8000-000000000001',
  recordId: '30000000-0000-4000-8000-000000000001',
  snapshotRef: designTasteCard.snapshotRef,
  ownership: TasteCardOwnership.saved,
  viewData: designTasteCard,
);

void main() {
  late _Cards cards;
  late AppRouter router;
  late TasteCardCoordinator coordinator;

  setUp(() {
    cards = _Cards();
    router = AppRouter(
      initialRoute: AppRoute.recordQuestions,
      child: const SizedBox.shrink(),
    );
    addTearDown(router.dispose);
    addTearDown(captureErrorReports((_, _, _) {}));
    coordinator = TasteCardCoordinator(
      _Host(router),
      AppGateways(
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        tasteCard: cards,
      ),
    )..startNew(TasteCardViewContext.repeatRecord);
  });

  Future<void> submit() => coordinator.submit(
    context: TasteCardViewContext.repeatRecord,
    requireAuthenticated: true,
    buildRequest: _request,
  );

  test('a card being made offers no way back; one that failed, or waits '
      'to be tried again, does', () async {
    expect(coordinator.isMakingCard, isFalse);

    unawaited(submit());
    expect(router.currentRoute, AppRoute.onboardingResult);
    expect(coordinator.isMakingCard, isTrue);
    expect(coordinator.newCardFailed, isFalse);

    cards.answers.single.completeError(StateError('offline'));
    await pumpEventQueue();
    expect(coordinator.isMakingCard, isFalse);
    expect(coordinator.newCardFailed, isTrue);
    // The questions are still behind the failed result.
    expect(router.stack, contains(AppRoute.recordQuestions));

    unawaited(coordinator.retry());
    expect(coordinator.isMakingCard, isTrue);
    cards.answers.last.complete(
      const TasteCardRetryableOutcome(
        idempotencyKey: 'key',
        attemptRef: 'attempt',
        error: TasteCardRetryError.engineTemporarilyUnavailable,
        retryAfter: null,
      ),
    );
    await pumpEventQueue();
    expect(coordinator.newCardFailed, isTrue);

    unawaited(coordinator.retry());
    cards.answers.last.complete(TasteCardFinalOutcome(_card));
    await pumpEventQueue();
    // A finished card leads on, not back.
    expect(coordinator.isMakingCard, isFalse);
    expect(coordinator.newCardFailed, isFalse);
    // The three sends were one record: the same key each time.
    expect(cards.requests.map((r) => r.idempotencyKey).toSet(), hasLength(1));
  });

  test('완료 pressed again while the same answers are on their way shows the '
      'waiting page and sends nothing more', () async {
    unawaited(submit());
    // Back on the questions, as a browser's back button can still do.
    router.pop();
    expect(router.currentRoute, AppRoute.recordQuestions);

    unawaited(submit());
    expect(router.currentRoute, AppRoute.onboardingResult);
    expect(coordinator.isMakingCard, isTrue);
    expect(cards.requests, hasLength(1));

    cards.answers.single.complete(TasteCardFinalOutcome(_card));
    await pumpEventQueue();
    expect(coordinator.state.result, _card);
  });

  test('a saved card being opened can be left, and its failure is not a '
      'new card that failed', () async {
    unawaited(coordinator.open(_card.resultId));
    await pumpEventQueue();
    expect(coordinator.showsSavedCard, isTrue);
    expect(coordinator.isMakingCard, isFalse);

    cards.opened.completeError(StateError('offline'));
    await pumpEventQueue();
    expect(coordinator.newCardFailed, isFalse);
  });
}
