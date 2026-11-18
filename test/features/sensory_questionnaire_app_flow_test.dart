import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/direct_aroma_choices.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/features/onboarding/data/sensory_questionnaire_data.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_choice_controls.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';

import '../support/app_test_harness.dart';
import '../support/fake_search.dart';
import '../support/test_catalog.dart';
import '../support/design_taste_card.dart';
import '../support/sensory_fixtures.dart';

SensoryQuestionnaireData _data() {
  final engine = aromaEngine();
  return SensoryQuestionnaireData(
    registry: sensoryRegistry(),
    aromaEngine: engine,
    aromas: engine.resolve(
      AromaProductContext(
        categoryKey: 'wine',
        styleKeys: ['red_wine'],
        aromaKeys: ['cherry'],
      ),
    ),
    aromaMenu: OnboardingAromaMenu.forDrink('wine', 'red_wine'),
    gauges: gaugesFor('wine', 'red_wine'),
  );
}

class _Gateway implements TasteCardGateway {
  @override
  Future<void> deleteOwnedResult(String resultId) => throw UnimplementedError();

  _Gateway({required this.isAuthenticated});
  @override
  final bool isAuthenticated;
  final requests = <CreateTasteCardResultRequest>[];

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequest request,
  ) async {
    requests.add(request);
    return TasteCardRetryableOutcome(
      idempotencyKey: request.idempotencyKey,
      attemptRef: 'test-attempt',
      error: TasteCardRetryError.engineTemporarilyUnavailable,
      retryAfter: null,
    );
  }

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequest request,
  ) => throw UnimplementedError();
  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) =>
      throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester, {
  required AppRoute initial,
  required _Gateway gateway,
  required SensoryQuestionnaireLoader loader,
}) async {
  tester.view.physicalSize = const Size(411, 891);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = AppRouter(
    initialRoute: initial,
    child: AppFlow(
      initialRoute: initial,
      catalogSearchGateway: FakeCatalog(const <CatalogDrink>[
        CatalogDrink(
          id: '11111111-1111-4111-8111-111111111111',
          displayName: '연결 테스트 와인',
          category: DrinkCategory.redWine,
        ),
      ]),
      tasteCardGateway: gateway,
      sensoryQuestionnaireLoader: loader,
    ),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerDelegate: router,
        routeInformationParser: AppRouteInformationParser(fallback: initial),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) =>
    tapSensoryOption(tester, 'sensory-next');

Future<void> _selectDrink(
  WidgetTester tester, {
  required bool onboarding,
}) async {
  if (onboarding) await startOnboarding(tester);
  await tester.enterText(find.byType(TextField), '연결 테스트');
  // Past the search screen's inline 250 ms typing debounce.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('연결 테스트 와인'));
  await _tap(tester, find.text('다음'));
}

const _reviewTitle = '고르신 것들 중 아쉬웠던 부분이 있나요?';

/// Answers something on every page of a red wine's questions, marks the
/// tannin as a burden on the review and presses 저장.
Future<void> _answerEveryPage(WidgetTester tester) async {
  expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);
  await tapSensoryOption(tester, 'revisit:wantAgain');
  await _next(tester);
  expect(find.text('잔에서 어떤 향이 느껴졌나요?'), findsOneWidget);
  await tapSensoryOption(tester, 'aroma:nose:black_cherry');
  await _next(tester);
  expect(find.text('입안에서 느껴진 맛과 질감은 어땠나요?'), findsOneWidget);
  await tapSensoryOption(tester, 'gauge:sweetness:2');
  await tapSensoryOption(tester, 'gauge:tannin:4');
  await tapSensoryOption(tester, 'aroma:palate:black_cherry');
  await _next(tester);
  expect(find.text('삼킨 뒤 남는 여운은 어땠나요?'), findsOneWidget);
  await tapSensoryOption(tester, 'gauge:finish_length:4');
  await tapSensoryOption(tester, 'aroma:finish:oak');
  await _next(tester);
  expect(find.text(_reviewTitle), findsOneWidget);
  expect(find.text('저장'), findsOneWidget);
  await tapSensoryOption(tester, 'review:level:tannin');
  await _next(tester);
}

/// What [_answerEveryPage] sends, whichever flow asked.
const _everyPageAnswers = [
  {
    'question_key': 'sensory_revisit',
    'selected_option_keys': ['revisit:wantAgain'],
    'free_text': null,
  },
  {
    'question_key': 'sensory_nose_aroma',
    'selected_option_keys': ['aroma:nose:black_cherry:liked'],
    'free_text': null,
  },
  {
    'question_key': 'sensory_palate_level',
    'selected_option_keys': [
      'level:sweetness:2:liked',
      'level:tannin:4:disliked',
    ],
    'free_text': null,
  },
  {
    'question_key': 'sensory_palate_aroma',
    'selected_option_keys': ['aroma:palate:black_cherry:liked'],
    'free_text': null,
  },
  {
    'question_key': 'sensory_finish_level',
    'selected_option_keys': ['level:finish_length:4:liked'],
    'free_text': null,
  },
  {
    'question_key': 'sensory_finish_aroma',
    'selected_option_keys': ['aroma:finish:oak:liked'],
    'free_text': null,
  },
];

void main() {
  final data = _data();

  testWidgets('onboarding retries loading, walks every page to the review, '
      'keeps answers on back and sends them', (tester) async {
    final gateway = _Gateway(isAuthenticated: false);
    final reported = <String>[];
    addTearDown(captureErrorReports((_, _, where) => reported.add(where)));
    var loads = 0;
    await _pump(
      tester,
      initial: AppRoute.onboardingWelcome,
      gateway: gateway,
      loader: (selection) async {
        expect(selection.catalogId, '11111111-1111-4111-8111-111111111111');
        loads++;
        if (loads == 1) throw Exception('network unavailable');
        return data;
      },
    );
    await _selectDrink(tester, onboarding: true);
    expect(find.text('질문을 불러오지 못했어요'), findsOneWidget);
    expect(reported, ['questionnaire']);
    await _tap(tester, find.text('다시 시도'));
    await _answerEveryPage(tester);
    // The review's 저장 submits; the result route shows the outcome.
    expect(gateway.requests, hasLength(1));
    expect(find.text('네트워크 연결이 불안정해요'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_reviewTitle), findsOneWidget);
    expect(loads, 2);
    await _next(tester);
    // Unchanged answers go out again under the same idempotency key.
    expect(gateway.requests, hasLength(2));
    expect(
      gateway.requests.last.idempotencyKey,
      gateway.requests.first.idempotencyKey,
    );
    final first = gateway.requests.first;
    expect(first.anonymousSessionId, isNotNull);
    expect(first.questionnaireVersion, 'sensory-questionnaire-v2');
    expect(first.answers.map((answer) => answer.toJson()), _everyPageAnswers);
    await _tap(tester, find.text('다시 시도'));
    expect(gateway.requests, hasLength(3));
    expect(gateway.requests.last.idempotencyKey, first.idempotencyKey);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // A changed answer is a new submission.
    await tapSensoryOption(tester, 'review:level:tannin');
    await _next(tester);
    expect(gateway.requests, hasLength(4));
    expect(gateway.requests.last.idempotencyKey, isNot(first.idempotencyKey));
    expect(
      gateway.requests.last.answers.expand((a) => a.selectedOptionKeys),
      contains('level:tannin:4:liked'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a repeat record asks the same pages as the first record and '
      'sends the same answers', (tester) async {
    final gateway = _Gateway(isAuthenticated: true);
    await _pump(
      tester,
      initial: AppRoute.recordSearch,
      gateway: gateway,
      loader: (_) async => data,
    );
    await _selectDrink(tester, onboarding: false);
    await _answerEveryPage(tester);
    final request = gateway.requests.single;
    expect(request.anonymousSessionId, isNull);
    expect(request.q7FreeText, isNull);
    expect(request.questionnaireVersion, 'sensory-questionnaire-v2');
    expect(request.answers.map((answer) => answer.toJson()), _everyPageAnswers);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SKIP keeps 재음용 의사 and the nose as unsure, and a record '
      'with nothing sensed is not sent: the finish waits for one answer', (
    tester,
  ) async {
    final gateway = _Gateway(isAuthenticated: true);
    await _pump(
      tester,
      initial: AppRoute.recordSearch,
      gateway: gateway,
      loader: (_) async => data,
    );
    await _selectDrink(tester, onboarding: false);
    expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);
    await tapSensoryOption(tester, 'revisit:unsure'); // the header's SKIP
    await tapSensoryOption(tester, 'nose:unsure');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // A page already skipped may be left again with 다음.
    expect(find.text('잔에서 어떤 향이 느껴졌나요?'), findsOneWidget);
    await _next(tester);
    await _next(tester);
    expect(find.text('삼킨 뒤 남는 여운은 어땠나요?'), findsOneWidget);
    // Nothing is sensed yet: 다음 does not answer, and the page says why.
    expect(find.text('향, 맛, 여운 중 하나 이상은 골라 주세요.'), findsOneWidget);
    await _next(tester);
    expect(find.text('삼킨 뒤 남는 여운은 어땠나요?'), findsOneWidget);
    expect(gateway.requests, isEmpty);
    await tapSensoryOption(tester, 'gauge:finish_length:4');
    await _next(tester);
    expect(find.text(_reviewTitle), findsOneWidget);
    await _next(tester);
    final request = gateway.requests.single;
    expect(request.answers.map((answer) => answer.toJson()), [
      {
        'question_key': 'sensory_revisit',
        'selected_option_keys': ['revisit:unsure'],
        'free_text': null,
      },
      {
        'question_key': 'sensory_nose_aroma',
        'selected_option_keys': ['nose:unsure'],
        'free_text': null,
      },
      {
        'question_key': 'sensory_finish_level',
        'selected_option_keys': ['level:finish_length:4:liked'],
        'free_text': null,
      },
    ]);
    expect(tester.takeException(), isNull);
  });

  group('record entry from home', () {
    testWidgets('record entry follows one search and question flow', (
      tester,
    ) async {
      await pumpAppAtRecordEntry(tester);

      expect(find.text('최근에 마신 술이 있나요?'), findsOneWidget);
      expect(find.text('건너뛸게요'), findsNothing);

      await _enterFixtureDrink(tester);
      // No photo page before the questions; it is added after the card.
      expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);

      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();
      expect(find.text('최근에 마신 술이 있나요?'), findsOneWidget);
    });

    testWidgets('the same drink chosen again finds its answers as they '
        'were left', (tester) async {
      await pumpAppAtRecordEntry(tester);
      await _enterFixtureDrink(tester);
      await tapSensoryOption(tester, 'revisit:wantAgain');
      await tapSensoryOption(tester, 'sensory-next');
      final aroma = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('aroma:nose:');
      }).first;
      await tester.ensureVisible(aroma);
      await tester.tap(aroma);
      await tester.pumpAndSettle();

      // Back to the first question, then to the drink search.
      for (var step = 0; step < 2; step++) {
        await tester.tap(find.byTooltip('이전 화면으로 이동'));
        await tester.pumpAndSettle();
      }
      expect(find.text('최근에 마신 술이 있나요?'), findsOneWidget);

      // The drink is still chosen there; 다음 goes on with it.
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);
      expect(
        tester
            .widget<OnboardingLargeOption>(
              find.byKey(const ValueKey('revisit:wantAgain')),
            )
            .selected,
        isTrue,
      );
      await tapSensoryOption(tester, 'sensory-next');
      // The aroma picked before is still picked.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppChip &&
              widget.selected &&
              (widget.key as ValueKey<String>?)?.value.startsWith(
                    'aroma:nose:',
                  ) ==
                  true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('back from a finished card leads to where the record began, '
        'not to the answers already sent', (tester) async {
      final gateway = _RecordingTasteCardGateway();
      await pumpAppAtRecordEntry(tester, gateway);
      await _enterFixtureDrink(tester);
      await tapSensoryOption(tester, 'revisit:wantAgain');
      await tapSensoryOption(tester, 'sensory-next');
      await completeSensoryQuestionsWithOneAnswer(tester);
      expect(find.byType(TasteCardScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TasteCardScreen), findsNothing);
      expect(find.byKey(const ValueKey('sensory-next')), findsNothing);
      expect(find.text('최근에 마신 술이 있나요?'), findsNothing);
      expect(gateway.requests, hasLength(1));
    });

    testWidgets(
      'authenticated repeat record submits straight from the review\'s 저장',
      (tester) async {
        final gateway = _RecordingTasteCardGateway();
        final recordNote = _RecordingNoteGateway();
        await pumpAppAtRecordEntry(tester, gateway, recordNote);
        await _enterFixtureDrink(tester);

        await tapSensoryOption(tester, 'revisit:wantAgain');
        await tapSensoryOption(tester, 'sensory-next');
        await tapSensoryOption(tester, 'nose:unsure');
        await tapSensoryOption(tester, 'gauge:sweetness:1');
        await tapSensoryOption(tester, 'sensory-next');
        await tapSensoryOption(tester, 'gauge:finish_length:5');
        await tapSensoryOption(tester, 'sensory-next');
        // The review is the last page; nothing is sent before its 저장.
        expect(find.text('저장'), findsOneWidget);
        expect(gateway.requests, isEmpty);
        await tapSensoryOption(tester, 'sensory-next');

        expect(gateway.requests, hasLength(1));
        final request = gateway.requests.single;
        expect(request.anonymousSessionId, isNull);
        expect(request.q7FreeText, isNull);
        expect(request.photoAssetId, isNull);
        expect(
          request.alcoholIdentification.alcoholNameSnapshot,
          '테스트 드라이 화이트 와인',
        );
        expect(
          request.alcoholIdentification.alcoholItemId,
          'fixture-dry-white-wine',
        );
        expect(request.answers.map((answer) => answer.questionKey), [
          'sensory_revisit',
          'sensory_nose_aroma',
          'sensory_palate_level',
          'sensory_finish_level',
        ]);
        expect(request.answers.expand((answer) => answer.selectedOptionKeys), [
          'revisit:wantAgain',
          'nose:unsure',
          'level:sweetness:1:liked',
          'level:finish_length:5:liked',
        ]);
        expect(find.byType(TasteCardScreen), findsOneWidget);
        // The 총평 is added from the header's 더보기, after the record;
        // only a card reopened from the saved list offers deletion.
        final more = find.byKey(const ValueKey('taste-card-more'));
        final menuNote = find.byKey(const ValueKey('taste-card-menu-overall'));
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('taste-card-menu-delete')),
          findsNothing,
        );
        expect(find.text('총평 남기기'), findsOneWidget);
        await tester.tap(menuNote);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('taste-card-note-field')),
          ' 과일 향이 오래 남아서 좋았어요. ',
        );
        await tester.tap(find.byKey(const ValueKey('taste-card-note-save')));
        await tester.pumpAndSettle();
        expect(recordNote.notes, {
          _RecordingTasteCardGateway.recordId: ' 과일 향이 오래 남아서 좋았어요. ',
        });
        // A saved 총평 is changed from the same item.
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(find.text('총평 수정'), findsOneWidget);
      },
    );
  });
}

/// Picks the fixture dry white wine from the local catalog list.
Future<void> _enterFixtureDrink(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '테스트 드라이');
  await pumpCatalogSearch(tester);
  await tester.tap(find.text('테스트 드라이 화이트 와인'));
  await tester.pump();
  await tester.ensureVisible(find.text('다음'));
  await tester.tap(find.text('다음'));
  await tester.pumpAndSettle();
}

class _RecordingNoteGateway implements RecordNoteGateway {
  final notes = <String, String>{};

  @override
  Future<String> loadNote(String recordId) async => notes[recordId] ?? '';

  @override
  Future<void> saveNote({
    required String recordId,
    required String note,
  }) async {
    notes[recordId] = note;
  }
}

class _RecordingTasteCardGateway implements TasteCardGateway {
  @override
  Future<void> deleteOwnedResult(String resultId) => throw UnimplementedError();

  static const recordId = '30000000-0000-4000-8000-000000000001';
  final List<CreateTasteCardResultRequest> requests =
      <CreateTasteCardResultRequest>[];

  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequest request,
  ) async {
    requests.add(request);
    final viewData = designTasteCard;
    return TasteCardFinalOutcome(
      TasteCardResult(
        resultId: '20000000-0000-4000-8000-000000000001',
        recordId: recordId,
        snapshotRef: viewData.snapshotRef,
        ownership: TasteCardOwnership.saved,
        viewData: viewData,
      ),
    );
  }

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequest request,
  ) => throw UnimplementedError();

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) =>
      throw UnimplementedError();
}
