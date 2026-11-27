import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/flows/app_gateways.dart';
import 'package:soolgyul/src/app/flows/flow_host.dart';
import 'package:soolgyul/src/app/flows/taste_card_coordinator.dart';
import 'package:soolgyul/src/app/state/sensory_session.dart';
import 'package:soolgyul/src/app/state/taste_card_flow_state.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/features/onboarding/data/sensory_questionnaire_data.dart';
import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/features/records/data/tasting_note_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';
import '../support/sensory_fixtures.dart';

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
  var opened = Completer<TasteCardResult>();

  /// False for a visitor without an account.
  bool signedIn = true;

  @override
  bool get isAuthenticated => signedIn;

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

  /// What a claim gives back.
  TasteCardResult? converted;

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequest request,
  ) async => converted ?? (throw UnimplementedError());
}

/// Keeps what is saved; [fails] refuses every save.
class _Notes implements TastingNoteGateway {
  _Notes({this.fails = false});

  final bool fails;
  final saved = <String, Map<String, Object?>>{};

  @override
  Future<Map<String, String>> load(String recordId) async => const {};

  @override
  Future<void> save(String recordId, Map<String, Object?> patch) async {
    if (fails) throw const TastingNoteException('offline');
    saved[recordId] = patch;
  }
}

CreateTasteCardResultRequest _request({
  required String idempotencyKey,
  String? anonymousSessionId,
  required Map<String, String> look,
}) => CreateTasteCardResultRequest(
  idempotencyKey: idempotencyKey,
  anonymousSessionId: anonymousSessionId,
  questionnaireVersion: 'test',
  alcoholIdentification: const AlcoholIdentificationInput.catalogMatch(
    alcoholItemId: 'drink',
    alcoholNameSnapshot: '테스트 와인',
  ),
  answers: const <QuestionnaireAnswerInput>[],
  look: look,
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

  group('the colour and texture asked with the questions', () {
    TasteCardCoordinator withNotes(_Notes notes) => TasteCardCoordinator(
      _Host(router),
      AppGateways(
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        tasteCard: cards,
        tastingNote: notes,
      ),
    )..startNew(TasteCardViewContext.repeatRecord);

    Future<void> submitWith(TasteCardCoordinator coordinator) =>
        coordinator.submit(
          context: TasteCardViewContext.repeatRecord,
          requireAuthenticated: true,
          buildRequest: _request,
          note: const {'appearance': 'ruby', 'appearance_texture': 'medium'},
        );

    test(
      'are kept on the record\'s tasting note before its card shows',
      () async {
        final notes = _Notes();
        final coordinator = withNotes(notes);
        unawaited(submitWith(coordinator));
        cards.answers.single.complete(TasteCardFinalOutcome(_card));
        await pumpEventQueue();
        expect(notes.saved, {
          _card.recordId: {
            'appearance': 'ruby',
            'appearance_texture': 'medium',
          },
        });
        expect(coordinator.state.result, _card);
        // A member's are saved to the note, not sent with the answers.
        expect(cards.requests.single.look, isEmpty);
        expect(cards.requests.single.toJson().containsKey('look'), isFalse);
      },
    );

    test('of a visitor\'s card go with its request, so the card carries '
        'them to whoever claims it, and a claim saves nothing again', () async {
      final notes = _Notes();
      final coordinator = withNotes(notes);
      cards.signedIn = false;
      unawaited(
        coordinator.submit(
          context: TasteCardViewContext.firstOnboarding,
          requireAuthenticated: false,
          buildRequest: _request,
          note: const {'appearance': 'ruby', 'appearance_texture': 'medium'},
        ),
      );
      final sent = cards.requests.single;
      expect(sent.anonymousSessionId, isNotNull);
      expect(sent.toJson()['look'], {
        'appearance': 'ruby',
        'appearance_texture': 'medium',
      });
      final anonymous = TasteCardResult(
        resultId: _card.resultId,
        snapshotRef: _card.snapshotRef,
        ownership: TasteCardOwnership.anonymous,
        viewData: designTasteCard,
      );
      cards.answers.single.complete(TasteCardFinalOutcome(anonymous));
      await pumpEventQueue();
      expect(notes.saved, isEmpty);

      // Claimed in the same open page: the server already holds the look.
      cards
        ..signedIn = true
        ..converted = _card;
      await coordinator.claim(
        TasteCardPendingConversion(
          anonymousSessionId: 'session',
          resultId: _card.resultId,
          snapshotRef: _card.snapshotRef,
          conversionToken: 'token',
        ),
      );
      expect(coordinator.state.result, _card);
      expect(notes.saved, isEmpty);
    });

    test('that fail to be kept leave the card as it is', () async {
      final coordinator = withNotes(_Notes(fails: true));
      unawaited(submitWith(coordinator));
      cards.answers.single.complete(TasteCardFinalOutcome(_card));
      await pumpEventQueue();
      expect(coordinator.state.result, _card);
      expect(coordinator.newCardFailed, isFalse);
    });
  });

  test('a visitor refused for having made the day\'s cards is told so, '
      'which no other failure is, and it is no fault to report', () async {
    final reports = <Object>[];
    addTearDown(captureErrorReports((error, _, _) => reports.add(error)));
    cards.signedIn = false;
    Future<void> submitAsVisitor() => coordinator.submit(
      context: TasteCardViewContext.firstOnboarding,
      requireAuthenticated: false,
      buildRequest: _request,
    );

    unawaited(submitAsVisitor());
    cards.answers.last.completeError(
      const TasteCardGatewayException(
        TasteCardGatewayOperation.create,
        code: 'anonymous_generation_limit_reached',
      ),
    );
    await pumpEventQueue();
    expect(coordinator.state.phase, TasteCardFlowPhase.visitorLimit);
    expect(reports, isEmpty);
    // The way back to the answers stays, as after any card not made.
    expect(coordinator.newCardFailed, isTrue);

    unawaited(coordinator.retry());
    cards.answers.last.completeError(
      const TasteCardGatewayException(
        TasteCardGatewayOperation.create,
        code: 'catalog_item_not_found',
      ),
    );
    await pumpEventQueue();
    expect(coordinator.state.phase, TasteCardFlowPhase.failure);
    expect(reports, hasLength(1));
  });

  test('a card the connection kept from being made waits to be tried '
      'again under the same key, and is no fault to report; any other '
      'failure is the card not made', () async {
    final reports = <Object>[];
    addTearDown(captureErrorReports((error, _, _) => reports.add(error)));
    final offline = TasteCardGatewayException(
      TasteCardGatewayOperation.create,
      cause: ConnectionFailure(TimeoutException('no answer')),
    );

    unawaited(submit());
    cards.answers.last.completeError(offline);
    await pumpEventQueue();
    expect(coordinator.state.phase, TasteCardFlowPhase.retryable);
    expect(reports, isEmpty);
    final key = coordinator.state.idempotencyKey;

    // The connection itself, not reworded by a gateway, reads the same.
    unawaited(coordinator.retry());
    cards.answers.last.completeError(ConnectionFailure('no route'));
    await pumpEventQueue();
    expect(coordinator.state.phase, TasteCardFlowPhase.retryable);

    unawaited(coordinator.retry());
    cards.answers.last.completeError(
      const TasteCardGatewayException(TasteCardGatewayOperation.create),
    );
    await pumpEventQueue();
    expect(coordinator.state.phase, TasteCardFlowPhase.failure);
    expect(reports, hasLength(1));

    unawaited(coordinator.retry());
    cards.answers.last.complete(TasteCardFinalOutcome(_card));
    await pumpEventQueue();
    expect(coordinator.state.result, _card);
    expect(cards.requests, hasLength(4));
    expect(cards.requests.map((r) => r.idempotencyKey).toSet(), {key});
  });

  test('a saved card the connection kept from opening says so; one the '
      'server could not give is the card not read', () async {
    unawaited(coordinator.open(_card.resultId));
    await pumpEventQueue();
    cards.opened.completeError(
      TasteCardGatewayException(
        TasteCardGatewayOperation.detail,
        cause: ConnectionFailure('no route'),
      ),
    );
    await pumpEventQueue();
    expect(coordinator.showsSavedCard, isTrue);
    expect(coordinator.state.phase, TasteCardFlowPhase.retryable);

    cards.opened = Completer<TasteCardResult>();
    unawaited(coordinator.retry());
    await pumpEventQueue();
    cards.opened.completeError(
      const TasteCardGatewayException(
        TasteCardGatewayOperation.detail,
        code: 'result_not_found',
      ),
    );
    await pumpEventQueue();
    expect(coordinator.state.phase, TasteCardFlowPhase.failure);
  });

  test('a look changed is another request for a visitor, whose look is '
      'sent with the answers; a member\'s is saved apart', () async {
    final data = SensoryQuestionnaireData(
      registry: sensoryRegistry(),
      aromaMenu: OnboardingAromaMenu.forDrink('wine', 'red_wine'),
      gauges: gaugesFor('wine', 'red_wine'),
    );
    final session = SensorySession()
      ..data = data
      ..flow = data.registry.createFlow(data.gauges);
    for (final (signedIn, changes) in [(true, isFalse), (false, isTrue)]) {
      cards.signedIn = signedIn;
      session.look.clear();
      coordinator
        ..reset()
        ..noteSensoryAnswersChanged(session);
      unawaited(
        coordinator.submit(
          context: TasteCardViewContext.firstOnboarding,
          requireAuthenticated: false,
          buildRequest: _request,
        ),
      );
      cards.answers.last.completeError(StateError('offline'));
      await pumpEventQueue();
      final key = coordinator.state.idempotencyKey;
      expect(key, isNotNull);

      session.look['appearance'] = 'ruby';
      coordinator.noteSensoryAnswersChanged(session);
      expect(coordinator.state.idempotencyKey != key, changes);
    }
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
