import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/direct_aroma_choices.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/core/sensory/finish_choices.dart';
import 'package:soolgyul/src/core/sensory/sensory_meanings.dart';
import 'package:soolgyul/src/core/sensory/sensory_option_definitions.dart';
import 'package:soolgyul/src/features/onboarding/data/sensory_questionnaire_data.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';
import 'package:soolgyul/src/features/onboarding/data/dictionary_views.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';

Map<String, dynamic> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

SensoryQuestionnaireData _data() {
  final vocabulary = serviceVocabularyView(
    _read('catalog/dictionary/terms.json'),
  );
  final engine = DirectAromaChoiceEngine(
    reference: _read('catalog/sensory/aroma-choice-reference.json'),
    vocabulary: vocabulary,
    sourceCatalog: sensoryCatalogView(_read('catalog/dictionary/terms.json')),
    alcoholTaxonomy: taxonomyView(_read('catalog/dictionary/terms.json')),
  );
  return SensoryQuestionnaireData(
    registry: SensoryMeaningRegistry(
      vocabulary: vocabulary,
      tasteBank: _read('catalog/sensory/palate-question-bank.json'),
      definitions: SensoryOptionDefinitions.fromJson(
        _read('catalog/sensory/answer-option-definitions.json'),
      ),
    ),
    aromaEngine: engine,
    aromas: engine.resolve(
      AromaProductContext(
        categoryKey: 'wine',
        styleKeys: ['red_wine'],
        aromaKeys: ['cherry'],
      ),
    ),
    aromaMenu: OnboardingAromaMenu.forCategory('wine'),
  );
}

class _Catalog implements CatalogSearchGateway {
  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async => [
    const CatalogDrink(
      id: '11111111-1111-4111-8111-111111111111',
      displayName: '연결 테스트 와인',
      category: DrinkCategory.redWine,
    ),
  ];
}

class _Gateway implements TasteCardGateway {
  @override
  Future<void> deleteOwnedResult(String resultId) => throw UnimplementedError();

  _Gateway({required this.isAuthenticated});
  @override
  final bool isAuthenticated;
  final requests = <CreateTasteCardResultRequestV1>[];

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequestV1 request,
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
    AnonymousTasteCardConversionRequestV1 request,
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
      catalogSearchGateway: _Catalog(),
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

Future<void> _key(WidgetTester tester, String key) =>
    _tap(tester, find.byKey(ValueKey(key)));
Future<void> _next(WidgetTester tester) => _key(tester, 'sensory-next');

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

void main() {
  final data = _data();

  testWidgets(
    'onboarding retries loading, keeps answers on back and submits sensory IDs',
    (tester) async {
      final gateway = _Gateway(isAuthenticated: false);
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
      expect(find.text('질문을 불러오지 못했어요. 다시 시도해주세요.'), findsOneWidget);
      await _key(tester, 'sensory-load-retry');
      expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);
      await _key(tester, 'revisit:wantAgain');
      await _next(tester);
      expect(find.text('좋았거나, 거슬렸던 향이 있나요?'), findsOneWidget);
      await _key(tester, 'notice:aroma:cherry'); // one tap: liked
      await _next(tester);
      await _key(tester, 'reaction:taste:acidity:liked');
      await _key(tester, 'reason:taste:acidity:harmony');
      await _key(tester, 'reaction:taste:sweetness:fine');
      await _key(tester, 'reaction:taste:bitterness:fine');
      await _next(tester);
      await _key(tester, 'mouthfeel:unsure');
      await _key(tester, 'finish:clean');
      await _next(tester);
      // The last question submits; the result route shows the outcome.
      expect(gateway.requests, hasLength(1));
      expect(find.text('잠시 연결이 원활하지 않아요'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(FinishQuestion.title), findsOneWidget);
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
      final keys = first.answers
          .expand((answer) => answer.selectedOptionKeys)
          .toSet();
      expect(
        keys,
        containsAll([
          'revisit:wantAgain',
          'notice:aroma:cherry',
          'reaction:aroma:cherry:liked',
          'reason:taste:acidity:liked:harmony',
          'mouthfeel:unsure',
          'finish:clean',
        ]),
      );
      await _tap(tester, find.text('다시 시도'));
      expect(gateway.requests, hasLength(3));
      expect(gateway.requests.last.idempotencyKey, first.idempotencyKey);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // A changed answer is a new submission.
      await _key(tester, 'finish:clean');
      await _next(tester);
      expect(gateway.requests, hasLength(4));
      expect(gateway.requests.last.idempotencyKey, isNot(first.idempotencyKey));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeat record uses the same questions and preserves unknown without legacy answers',
    (tester) async {
      final gateway = _Gateway(isAuthenticated: true);
      await _pump(
        tester,
        initial: AppRoute.recordSearch,
        gateway: gateway,
        loader: (_) async => data,
      );
      await _selectDrink(tester, onboarding: false);
      expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);
      await _key(tester, 'revisit:unsure'); // the header's SKIP
      await _key(tester, 'aroma:unsure');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('좋았거나, 거슬렸던 향이 있나요?'), findsOneWidget);
      await _next(tester);
      await _key(tester, 'reaction:taste:sweetness:fine');
      await _key(tester, 'reaction:taste:acidity:fine');
      await _key(tester, 'reaction:taste:bitterness:fine');
      await _next(tester);
      await _key(tester, 'mouthfeel:unsure');
      await _key(tester, 'finish:unsure');
      expect(gateway.requests, hasLength(1));
      final request = gateway.requests.single;
      expect(request.anonymousSessionId, isNull);
      expect(request.q7FreeText, isNull);
      expect(request.answers.map((answer) => answer.questionKey).toSet(), {
        'sensory_revisit',
        'sensory_aroma',
        'sensory_taste',
        'sensory_mouthfeel',
        'sensory_finish',
      });
      expect(
        request.answers.expand((answer) => answer.selectedOptionKeys).toSet(),
        {
          'revisit:unsure',
          'aroma:unsure',
          'reaction:taste:sweetness:fine',
          'reaction:taste:acidity:fine',
          'reaction:taste:bitterness:fine',
          'mouthfeel:unsure',
          'finish:unsure',
        },
      );
      expect(tester.takeException(), isNull);
    },
  );

  group('record entry from home', () {
    testWidgets('record entry follows one search and question flow', (
      tester,
    ) async {
      await pumpAppAtRecordEntry(tester);

      expect(find.text('최근에 마신 술은 무엇인가요?'), findsOneWidget);
      expect(find.text('건너뛸게요'), findsNothing);

      await _enterFixtureDrink(tester);
      // No photo page before the questions; it is added after the card.
      expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);

      await tester.tap(find.byTooltip('뒤로가기'));
      await tester.pumpAndSettle();
      expect(find.text('최근에 마신 술은 무엇인가요?'), findsOneWidget);
    });

    testWidgets(
      'authenticated repeat record submits straight from the last question',
      (tester) async {
        final gateway = _RecordingTasteCardGateway();
        final recordNote = _RecordingNoteGateway();
        await pumpAppAtRecordEntry(tester, gateway, recordNote);
        await _enterFixtureDrink(tester);

        await tapSensoryOption(tester, 'revisit:wantAgain');
        await tapSensoryOption(tester, 'sensory-next');
        await tapSensoryOption(tester, 'aroma:unsure');
        await tapSensoryOption(tester, 'reaction:taste:sweetness:liked');
        await tapSensoryOption(tester, 'reason:taste:sweetness:gentle');
        await answerAllTastesFine(tester, except: {'sweetness'});
        await tapSensoryOption(tester, 'mouthfeel:unsure');
        await tapSensoryOption(tester, 'finish:aromaEcho');
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
        expect(
          request.answers.map((answer) => answer.questionKey),
          containsAll(<String>[
            'sensory_revisit',
            'sensory_aroma',
            'sensory_taste',
            'sensory_mouthfeel',
            'sensory_finish',
          ]),
        );
        expect(
          request.answers.expand((answer) => answer.selectedOptionKeys),
          containsAll([
            'reaction:taste:sweetness:liked',
            'reason:taste:sweetness:liked:gentle',
            'finish:aromaEcho',
          ]),
        );
        expect(find.byType(TasteCardScreen), findsOneWidget);
        // The note is added from the header's 더보기, after the record;
        // only a card reopened from the saved list offers deletion.
        final more = find.byKey(const ValueKey('taste-card-more'));
        final menuNote = find.byKey(const ValueKey('taste-card-menu-note'));
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('taste-card-menu-delete')),
          findsNothing,
        );
        expect(find.text('메모 작성'), findsOneWidget);
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
        // The saved note opens in the term balloon.
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(find.text('메모 보기'), findsOneWidget);
        await tester.tap(menuNote);
        await tester.pumpAndSettle();
        expect(find.text('나의 메모'), findsOneWidget);
        expect(find.text('과일 향이 오래 남아서 좋았어요.'), findsOneWidget);
      },
    );
  });
}

/// Picks the fixture dry white wine from the local catalog list.
Future<void> _enterFixtureDrink(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '테스트 드라이');
  await tester.pump();
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
  final List<CreateTasteCardResultRequestV1> requests =
      <CreateTasteCardResultRequestV1>[];

  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequestV1 request,
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
    AnonymousTasteCardConversionRequestV1 request,
  ) => throw UnimplementedError();

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) =>
      throw UnimplementedError();
}
