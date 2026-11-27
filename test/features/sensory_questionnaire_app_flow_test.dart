import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/features/onboarding/data/sensory_questionnaire_data.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/records/data/tasting_note_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_appearance_choices.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';
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
import '../support/taste_card_envelopes.dart';

SensoryQuestionnaireData _data() {
  return SensoryQuestionnaireData(
    registry: sensoryRegistry(),
    aromaMenu: OnboardingAromaMenu.forDrink('wine', 'red_wine'),
    gauges: gaugesFor('wine', 'red_wine'),
    appearance: TasteCardAppearanceChoices.fromJson(
      readJsonAsset('catalog/sensory/appearance.json'),
    ).forDrink('wine', 'red_wine'),
  );
}

/// Keeps what is saved to a record's tasting note and gives it back.
class _Notes implements TastingNoteGateway {
  final saved = <String?, Map<String, Object?>>{};

  @override
  Future<Map<String, String>> load(String recordId) async => {
    for (final MapEntry(:key, :value) in (saved[recordId] ?? {}).entries)
      if (value case final String value) key: value,
  };

  @override
  Future<void> save(String recordId, Map<String, Object?> patch) async =>
      saved[recordId] = {...?saved[recordId], ...patch};
}

class _Gateway implements TasteCardGateway {
  @override
  Future<void> deleteOwnedResult(String resultId) => throw UnimplementedError();

  _Gateway({required this.isAuthenticated, this.createFailure, this.card});
  @override
  final bool isAuthenticated;
  final requests = <CreateTasteCardResultRequest>[];

  /// What making a card fails with; null has the server ask to be tried
  /// again.
  final Object? createFailure;

  /// The card made; null has the server ask to be tried again.
  final TasteCardResult? card;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequest request,
  ) async {
    requests.add(request);
    if (createFailure case final failure?) throw failure;
    if (card case final card?) return TasteCardFinalOutcome(card);
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
  TastingNoteGateway? notes,
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
      tastingNoteGateway: notes,
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

const _reviewTitle = '아쉬웠던 부분이 있으면 골라주세요.';

/// Answers something on every page of a red wine's questions, marks the
/// tannin as a burden on the review and presses 저장.
Future<void> _answerEveryPage(
  WidgetTester tester, {
  String revisitTitle = '재음용 의사',
}) async {
  expect(find.text(revisitTitle), findsOneWidget);
  await tapSensoryOption(tester, 'revisit:wantAgain');
  await _next(tester);
  expect(find.text('향(Aroma)'), findsOneWidget);
  await tapSensoryOption(tester, 'aroma:nose:black_cherry');
  await _next(tester);
  expect(find.text('맛과 질감(Palate)'), findsOneWidget);
  await tapSensoryOption(tester, 'gauge:sweetness:2');
  await tapSensoryOption(tester, 'gauge:tannin:4');
  // The finish stands under the palate's gauges, on the same page.
  expect(find.text('여운(Finish)'), findsOneWidget);
  await tapSensoryOption(tester, 'gauge:finish_length:4');
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
      // Gauges left untouched are sent at the middle step they start on.
      'level:acidity:3:liked',
      'level:body:3:liked',
      'level:tannin:4:disliked',
    ],
    'free_text': null,
  },
  {
    'question_key': 'sensory_finish_level',
    'selected_option_keys': [
      'level:finish_length:4:liked',
      'level:finish_character:3:liked',
    ],
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

  testWidgets('offline at 다음: the questions\' page says the connection '
      'after the one failed read, with no report, and loads on 다시 시도', (
    tester,
  ) async {
    final reported = <String>[];
    addTearDown(captureErrorReports((_, _, where) => reported.add(where)));
    var loads = 0;
    final answer = Completer<SensoryQuestionnaireData>();
    await _pump(
      tester,
      initial: AppRoute.onboardingWelcome,
      gateway: _Gateway(isAuthenticated: false),
      loader: (selection) {
        loads++;
        return loads == 1
            ? Future.error(ConnectionFailure(TimeoutException('no answer')))
            : answer.future;
      },
    );
    await _selectDrink(tester, onboarding: true);
    expect(loads, 1);
    expect(find.text('네트워크 연결이 불안정해요'), findsOneWidget);
    expect(find.text('연결을 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
    expect(find.text('질문을 불러오지 못했어요'), findsNothing);
    expect(reported, isEmpty);

    // The retry waits with a line under the spinner, not a blank page.
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('질문을 불러오고 있어요'), findsOneWidget);
    answer.complete(data);
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('재음용 의사'), findsOneWidget);
  });

  testWidgets('offline at 분석: the result says the connection and keeps the '
      'answers for the retry; any other failure says the card was not made', (
    tester,
  ) async {
    addTearDown(captureErrorReports((_, _, _) {}));
    for (final (failure, title) in [
      (
        TasteCardGatewayException(
          TasteCardGatewayOperation.create,
          cause: ConnectionFailure('no route'),
        ),
        '네트워크 연결이 불안정해요',
      ),
      (
        const TasteCardGatewayException(TasteCardGatewayOperation.create),
        '술결 카드를 완성하지 못했어요',
      ),
    ]) {
      final gateway = _Gateway(isAuthenticated: false, createFailure: failure);
      await _pump(
        tester,
        initial: AppRoute.onboardingWelcome,
        gateway: gateway,
        loader: (_) async => data,
      );
      await _selectDrink(tester, onboarding: true);
      await _answerEveryPage(tester);
      expect(find.text(title), findsOneWidget);
      await _tap(tester, find.text('다시 시도'));
      expect(gateway.requests, hasLength(2));
      expect(
        gateway.requests.last.idempotencyKey,
        gateway.requests.first.idempotencyKey,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a member\'s first card is theirs to write on at once, as '
      'every card after it is: 수정, the note\'s offer and the look chosen', (
    tester,
  ) async {
    // A red wine's card as the server sends it, whose note offers 색 and
    // 점성.
    final envelope = validEnvelope();
    viewOf(envelope)['note'] = viewOf(
      readJsonAsset(
        'supabase/functions/_tests/fixtures/taste_card_envelope_v3.json',
      ),
    )['note'];
    final card = TasteCardResult(
      resultId: '20000000-0000-4000-8000-000000000001',
      recordId: '30000000-0000-4000-8000-000000000001',
      snapshotRef: 'snapshot-v3',
      ownership: TasteCardOwnership.saved,
      viewData: TasteCardWireParser.parseResult(envelope).viewData,
    );
    // The first record walks the onboarding's pages, a later one the
    // record's own.
    for (final first in [AppRoute.onboardingSearch, AppRoute.recordSearch]) {
      final notes = _Notes();
      await _pump(
        tester,
        initial: first,
        gateway: _Gateway(isAuthenticated: true, card: card),
        loader: (_) async => data,
        notes: notes,
      );
      await _selectDrink(tester, onboarding: false);
      final medium = find.byKey(
        const ValueKey<String>(
          'taste-card-note-option-appearance_texture-medium',
        ),
      );
      await tester.ensureVisible(medium);
      await tester.tap(medium);
      await tester.pump();
      await _answerEveryPage(tester);

      final screen = tester.widget<TasteCardScreen>(
        find.byType(TasteCardScreen),
      );
      expect(screen.noteEntries, isNotNull, reason: '$first');
      expect(screen.noteOpener, isNotNull, reason: '$first');
      expect(screen.offerNoteForm, isTrue, reason: '$first');
      // The look chosen with the answers is on the record's note.
      expect(notes.saved, {
        card.recordId: {'appearance_texture': 'medium'},
      }, reason: '$first');
      // The header's 더보기 holds 수정.
      await _tap(tester, find.byKey(const ValueKey('taste-card-more')));
      expect(
        find.byKey(const ValueKey('taste-card-menu-edit')),
        findsOneWidget,
        reason: '$first',
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      // The first visit to the note offers to fill in the rest.
      await _tap(tester, find.byKey(const ValueKey('taste-card-tab-note')));
      expect(find.text('테이스팅 노트를 채웠어요.'), findsOneWidget, reason: '$first');
      await _tap(tester, find.text('나중에'));
      // Drawn from the record's own note, not from what the card was sent
      // with.
      expect(find.text('점성'), findsOneWidget, reason: '$first');
      expect(find.text('매끄럽고 적당함'), findsOneWidget, reason: '$first');
      expect(find.text('진득하고 오일리함'), findsNothing, reason: '$first');
      await tester.pumpWidget(const SizedBox());
    }
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
    await _answerEveryPage(tester, revisitTitle: '재음용 의사');
    final request = gateway.requests.single;
    expect(request.anonymousSessionId, isNull);
    expect(request.q7FreeText, isNull);
    expect(request.questionnaireVersion, 'sensory-questionnaire-v2');
    expect(request.answers.map((answer) => answer.toJson()), _everyPageAnswers);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a repeat record asks 재음용 의사 on one line with the colour '
      'and texture under it', (tester) async {
    final gateway = _Gateway(isAuthenticated: true);
    await _pump(
      tester,
      initial: AppRoute.recordSearch,
      gateway: gateway,
      loader: (_) async => data,
    );
    await _selectDrink(tester, onboarding: false);
    expect(find.text('재음용 의사'), findsOneWidget);
    final answers = ['있음', '애매해요', '없음'].map(find.text).toList();
    for (final answer in answers) {
      expect(answer, findsOneWidget);
    }
    // One line: the three stand at the same height.
    final top = tester.getTopLeft(answers.first).dy;
    for (final answer in answers.skip(1)) {
      expect(tester.getTopLeft(answer).dy, top);
    }
    expect(find.text('색상'), findsOneWidget);
    expect(find.text('질감'), findsOneWidget);
    // Below the answers: 색상, then 질감.
    expect(tester.getTopLeft(find.text('색상')).dy, greaterThan(top));
    expect(
      tester.getTopLeft(find.text('질감')).dy,
      greaterThan(tester.getTopLeft(find.text('색상')).dy),
    );
    expect(find.text('자줏빛'), findsOneWidget);
    expect(find.text('매끄럽고 적당함'), findsOneWidget);
  });

  testWidgets('SKIP keeps 재음용 의사 and the nose as unsure, and a record '
      'whose gauges are left where they start is sent with them at the '
      'middle: the finish does not wait', (tester) async {
    final gateway = _Gateway(isAuthenticated: true);
    await _pump(
      tester,
      initial: AppRoute.recordSearch,
      gateway: gateway,
      loader: (_) async => data,
    );
    await _selectDrink(tester, onboarding: false);
    expect(find.text('재음용 의사'), findsOneWidget);
    await tapSensoryOption(tester, 'revisit:unsure'); // the header's SKIP
    await tapSensoryOption(tester, 'nose:unsure');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // A page already skipped may be left again with 다음.
    expect(find.text('향(Aroma)'), findsOneWidget);
    await _next(tester);
    expect(find.text('여운(Finish)'), findsOneWidget);
    // Every gauge starts on its middle step, which is an answer: the page
    // has nothing to wait for.
    expect(find.text('향, 맛, 여운 중 하나 이상은 골라 주세요.'), findsNothing);
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
        'question_key': 'sensory_palate_level',
        'selected_option_keys': [
          'level:sweetness:3:liked',
          'level:acidity:3:liked',
          'level:body:3:liked',
          'level:tannin:3:liked',
        ],
        'free_text': null,
      },
      {
        'question_key': 'sensory_finish_level',
        'selected_option_keys': [
          'level:finish_length:4:liked',
          'level:finish_character:3:liked',
        ],
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

      expect(find.text('기록하고자 하는 술을 골라주세요.'), findsOneWidget);
      expect(find.text('건너뛸게요'), findsNothing);

      await _enterFixtureDrink(tester);
      // No photo page before the questions; it is added after the card.
      expect(find.text('재음용 의사'), findsOneWidget);

      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();
      expect(find.text('기록하고자 하는 술을 골라주세요.'), findsOneWidget);
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
      expect(find.text('기록하고자 하는 술을 골라주세요.'), findsOneWidget);

      // The drink is still chosen there; 다음 goes on with it.
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('재음용 의사'), findsOneWidget);
      expect(
        tester
            .widget<AppChip>(find.byKey(const ValueKey('revisit:wantAgain')))
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
      expect(find.text('기록하고자 하는 술을 골라주세요.'), findsNothing);
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
          'level:acidity:3:liked',
          'level:body:3:liked',
          'level:finish_length:5:liked',
          'level:finish_character:3:liked',
        ]);
        expect(find.byType(TasteCardScreen), findsOneWidget);
        // In the app the header closes the card, and its 더보기 holds 수정 and 삭제;
        // 수정 turns to the 테이스팅 노트, where the 총평 is written.
        expect(find.byKey(const ValueKey('app-top-bar-close')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('taste-card-more')));
        await tester.pumpAndSettle();
        expect(find.text('삭제'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('taste-card-menu-edit')));
        await tester.pumpAndSettle();
        // This card has no note, so 수정 opens its 총평 at once.
        await tester.enterText(
          find.byKey(const ValueKey('taste-card-note-field')),
          ' 과일 향이 오래 남아서 좋았어요. ',
        );
        await tester.tap(find.byKey(const ValueKey('taste-card-note-save')));
        await tester.pumpAndSettle();
        expect(recordNote.notes, {
          _RecordingTasteCardGateway.recordId: ' 과일 향이 오래 남아서 좋았어요. ',
        });
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
