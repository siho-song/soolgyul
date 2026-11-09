import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/catalog_drink.dart';
import 'package:soolgyul/src/features/onboarding/revisit_intent.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/finish_choices.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/sensory_meanings.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/sensory_option_definitions.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/sensory_question_flow.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/taste_reactions.dart';
import 'package:soolgyul/src/features/taste_card/data/sensory_submission.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_submission_mapper.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/onboarding/data/dictionary_views.dart';

const _namedDrink = DrinkSelection.catalogMatch(
  CatalogDrink(
    id: '30000000-0000-4000-8000-000000000001',
    displayName: '테스트 술',
    category: DrinkCategory.other,
  ),
);

void main() {
  late SensoryMeaningRegistry registry;
  late SensoryQuestionFlow flow;

  setUp(() {
    Map<String, dynamic> read(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    registry = SensoryMeaningRegistry(
      vocabulary: serviceVocabularyView(read('catalog/dictionary/terms.json')),
      tasteBank: read('catalog/sensory/palate-question-bank.json'),
      definitions: SensoryOptionDefinitions.fromJson(
        read('catalog/sensory/answer-option-definitions.json'),
      ),
    );
    flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
  });

  CreateTasteCardResultRequestV1 submit({
    DrinkSelection selection = _namedDrink,
    String? anonymousSessionId,
    SensoryQuestionFlow? selectedFlow,
  }) => TasteCardSubmissionMapper.fromSensoryFlow(
    idempotencyKey: 'same-attempt-id',
    anonymousSessionId: anonymousSessionId,
    selection: selection,
    flow: selectedFlow ?? flow,
    registry: registry,
  );

  QuestionnaireAnswerInputV1 answer(String key) =>
      submit().answers.singleWhere((answer) => answer.questionKey == key);

  test('uses the existing wire with raw IDs and no note or photo', () {
    flow.toggleNotice(SensorySection.aroma, 'vanilla');
    flow.toggleReaction(SensorySection.aroma, 'vanilla', TasteReaction.liked);
    flow.toggleReaction(
      SensorySection.taste,
      'sweetness',
      TasteReaction.disliked,
    );
    flow.toggleReason(SensorySection.taste, 'sweetness', 'too_strong');
    flow.toggleNotice(SensorySection.mouthfeel, 'heavy');
    flow.finish.toggle(FinishOption.heavy);

    final request = submit(anonymousSessionId: 'anonymous-session');
    final raw = request.toJson();
    expect(raw['questionnaire_version'], 'sensory-questionnaire-v1');
    expect(raw['anonymous_session_id'], 'anonymous-session');
    expect(raw['idempotency_key'], 'same-attempt-id');
    expect(raw['q7_free_text'], isNull);
    expect(raw['photo_asset_id'], isNull);
    expect(
      request.answers.map((answer) => answer.questionKey),
      SensorySubmission.questionKeys,
    );
    final allKeys = request.answers.expand(
      (answer) => answer.selectedOptionKeys,
    );
    expect(
      allKeys.toSet(),
      registry.readAnswers(flow).map((value) => value.id).toSet(),
    );
    expect(allKeys, contains('reason:taste:sweetness:disliked:too_strong'));
    expect(allKeys, isNot(contains('target:taste:sweetness:disliked')));
    expect(answer('sensory_mouthfeel').selectedOptionKeys, [
      'notice:mouthfeel:heavy',
    ]);
    expect(answer('sensory_finish').selectedOptionKeys, ['finish:heavy']);
    for (final snapshot in request.answers) {
      expect(snapshot.toJson().keys.toSet(), {
        'question_key',
        'selected_option_keys',
        'free_text',
      });
      expect(snapshot.freeText, isNull);
    }
  });

  test(
    'positive reactions submit without the retired character or unspecified reason',
    () {
      flow.toggleNotice(SensorySection.aroma, 'cherry');
      flow.toggleReaction(SensorySection.aroma, 'cherry', TasteReaction.liked);
      flow.toggleReaction(
        SensorySection.taste,
        'sweetness',
        TasteReaction.liked,
      );
      for (final retired in ['character', 'unspecified']) {
        expect(
          () => flow.toggleReason(SensorySection.taste, 'sweetness', retired),
          throwsArgumentError,
        );
      }
      flow.toggleReason(SensorySection.taste, 'sweetness', 'gentle');
      expect(answer('sensory_aroma').selectedOptionKeys, [
        'notice:aroma:cherry',
        'reaction:aroma:cherry:liked',
      ]);
      expect(answer('sensory_taste').selectedOptionKeys, [
        'reaction:taste:sweetness:liked',
        'reason:taste:sweetness:liked:gentle',
      ]);
      expect(
        submit().answers.expand((answer) => answer.selectedOptionKeys),
        isNot(contains('reason:aroma:cherry:liked:character')),
      );
    },
  );

  test(
    'unanswered sections do not become unknown, absence, neutral or dislike',
    () {
      final request = submit();
      expect(request.answers, hasLength(1));
      expect(request.answers.single.questionKey, 'sensory_revisit');
      expect(request.answers.single.selectedOptionKeys, ['revisit:wantAgain']);
      expect(request.q7FreeText, isNull);
    },
  );

  test('explicit unsure keeps its own ID and tastes cannot be unsure', () {
    flow.setUnsure(SensorySection.aroma);
    expect(() => flow.setUnsure(SensorySection.taste), throwsArgumentError);
    flow.toggleReaction(SensorySection.taste, 'sweetness', TasteReaction.fine);
    flow.finish.toggleUnsure();
    expect(answer('sensory_aroma').selectedOptionKeys, ['aroma:unsure']);
    expect(answer('sensory_taste').selectedOptionKeys, [
      'reaction:taste:sweetness:fine',
    ]);
    expect(answer('sensory_finish').selectedOptionKeys, ['finish:unsure']);
    expect(
      submit().answers.any((value) => value.questionKey == 'sensory_mouthfeel'),
      isFalse,
    );
    flow.toggleReaction(SensorySection.taste, 'acidity', TasteReaction.liked);
    expect(answer('sensory_taste').selectedOptionKeys, [
      'reaction:taste:acidity:liked',
      'reaction:taste:sweetness:fine',
    ]);
  });

  test(
    'every reacted taste carries its own reasons, no target, and a changed answer drops stale reasons',
    () {
      flow.toggleReaction(
        SensorySection.taste,
        'sweetness',
        TasteReaction.liked,
      );
      flow.toggleReaction(SensorySection.taste, 'acidity', TasteReaction.liked);
      flow.toggleReason(SensorySection.taste, 'sweetness', 'gentle');
      flow.toggleReason(SensorySection.taste, 'acidity', 'harmony');
      expect(answer('sensory_taste').selectedOptionKeys, [
        'reaction:taste:acidity:liked',
        'reaction:taste:sweetness:liked',
        'reason:taste:acidity:liked:harmony',
        'reason:taste:sweetness:liked:gentle',
      ]);
      flow.toggleReaction(
        SensorySection.taste,
        'sweetness',
        TasteReaction.disliked,
      );
      final keys = answer('sensory_taste').selectedOptionKeys;
      expect(keys, isNot(contains(startsWith('target:'))));
      expect(keys, isNot(contains('reason:taste:sweetness:liked:gentle')));
      expect(keys, contains('reason:taste:acidity:liked:harmony'));
      expect(keys, contains('reaction:taste:sweetness:disliked'));
    },
  );

  test(
    'request snapshots are detached from later answer edits and immutable',
    () {
      flow.toggleNotice(SensorySection.aroma, 'vanilla');
      final request = submit();
      final before = jsonEncode(request.toJson());
      flow.setUnsure(SensorySection.aroma);
      expect(jsonEncode(request.toJson()), before);
      expect(() => request.answers.clear(), throwsUnsupportedError);
      expect(
        () => request.answers.last.selectedOptionKeys.clear(),
        throwsUnsupportedError,
      );
      expect(answer('sensory_aroma').selectedOptionKeys, ['aroma:unsure']);
    },
  );

  test('equivalent selection orders produce identical retry payloads', () {
    final other = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    flow.toggleNotice(SensorySection.mouthfeel, 'smooth');
    flow.toggleNotice(SensorySection.mouthfeel, 'light');
    other.toggleNotice(SensorySection.mouthfeel, 'light');
    other.toggleNotice(SensorySection.mouthfeel, 'smooth');
    expect(
      jsonEncode(submit().toJson()),
      jsonEncode(submit(selectedFlow: other).toJson()),
    );
  });

  test(
    'all selectable observations stay inside unchanged wire cardinality limits',
    () {
      final aromas = registry.aromaKeys.toList()..sort();
      for (final key in aromas.take(5)) {
        flow.toggleNotice(SensorySection.aroma, key);
        flow.toggleReaction(SensorySection.aroma, key, TasteReaction.liked);
      }
      for (final key in SensoryQuestionFlow.tasteKeys) {
        flow.toggleReaction(
          SensorySection.taste,
          key,
          {'sweetness', 'acidity'}.contains(key)
              ? TasteReaction.liked
              : TasteReaction.disliked,
        );
      }
      for (final key in ['sweetness', 'acidity']) {
        for (final reason in ['gentle', 'pronounced', 'harmony']) {
          flow.toggleReason(SensorySection.taste, key, reason);
        }
      }
      for (final reason in ['too_strong', 'too_weak', 'disharmony']) {
        flow.toggleReason(SensorySection.taste, 'bitterness', reason);
      }
      for (final key in SensoryQuestionFlow.mouthfeelKeys) {
        flow.toggleNotice(SensorySection.mouthfeel, key);
        flow.toggleReaction(SensorySection.mouthfeel, key, TasteReaction.liked);
      }
      for (final option in FinishOption.values) {
        flow.finish.toggle(option);
      }
      final request = submit();
      expect(request.answers, hasLength(5));
      expect(
        request.answers.map((answer) => answer.selectedOptionKeys.length),
        [1, 10, 12, 12, 6],
      );
      expect(
        request.answers.every(
          (answer) => answer.selectedOptionKeys.length <= 20,
        ),
        isTrue,
      );
      expect(
        request.answers.expand((answer) => answer.selectedOptionKeys).length,
        registry.readAnswers(flow).length,
      );
    },
  );

  test(
    'anonymous and authenticated paths use the same raw answers and identification',
    () {
      const selection = DrinkSelection.catalogMatch(
        CatalogDrink(
          id: 'catalog-item-id',
          displayName: '카탈로그 술',
          category: DrinkCategory.whiteWine,
        ),
      );
      final anonymous = submit(
        selection: selection,
        anonymousSessionId: 'session',
      );
      final authenticated = submit(selection: selection);
      expect(
        anonymous.answers.map((a) => a.toJson()),
        authenticated.answers.map((a) => a.toJson()),
      );
      expect(authenticated.anonymousSessionId, isNull);
      expect(
        authenticated.alcoholIdentification.toJson(),
        anonymous.alcoholIdentification.toJson(),
      );
      expect(
        authenticated.alcoholIdentification.toJson()['alcohol_item_id'],
        'catalog-item-id',
      );
      expect(authenticated.alcoholIdentification.toJson()['category'], 'wine');
      expect(submit().alcoholIdentification.toJson(), <String, Object?>{
        'mode': 'catalog_match',
        'alcohol_item_id': '30000000-0000-4000-8000-000000000001',
        'alcohol_name_snapshot': '테스트 술',
        'category': null,
      });
    },
  );

  test('required answers and drink name fail closed before submission', () {
    expect(() => submit(selectedFlow: registry.createFlow()), throwsStateError);
    expect(
      () => submit(
        selection: const DrinkSelection.catalogMatch(
          CatalogDrink(
            id: 'blank',
            displayName: '  ',
            category: DrinkCategory.other,
          ),
        ),
      ),
      throwsStateError,
    );
  });

  test('cross-language fixture comes from the production sensory mapper', () {
    for (final key in ['apple', 'pear']) {
      flow.toggleNotice(SensorySection.aroma, key);
      flow.toggleReaction(SensorySection.aroma, key, TasteReaction.liked);
    }
    flow.toggleReaction(SensorySection.taste, 'sweetness', TasteReaction.liked);
    flow.toggleReason(SensorySection.taste, 'sweetness', 'pronounced');
    flow.toggleReaction(
      SensorySection.taste,
      'acidity',
      TasteReaction.disliked,
    );
    flow.toggleReason(SensorySection.taste, 'acidity', 'too_weak');
    flow.toggleNotice(SensorySection.mouthfeel, 'heavy');
    flow.toggleNotice(SensorySection.mouthfeel, 'warmth');
    flow.toggleReaction(
      SensorySection.mouthfeel,
      'warmth',
      TasteReaction.disliked,
    );
    flow.finish.toggle(FinishOption.heavy);
    flow.finish.toggle(FinishOption.pleasantLength);
    flow.finish.toggle(FinishOption.offFlavor);
    final payload = TasteCardSubmissionMapper.fromSensoryFlow(
      idempotencyKey: '10000000-0000-4000-8000-000000000001',
      anonymousSessionId: 'sensory-test',
      selection: _namedDrink,
      flow: flow,
      registry: registry,
    ).toJson();
    expect((payload['answers'] as List).map((row) => row['question_key']), [
      'sensory_revisit',
      'sensory_aroma',
      'sensory_taste',
      'sensory_mouthfeel',
      'sensory_finish',
    ]);
    final sharedFixture = jsonDecode(
      File(
        'supabase/functions/_tests/fixtures/sensory_flutter_wire_v1.json',
      ).readAsStringSync(),
    );
    expect(payload, sharedFixture);
    if (const bool.fromEnvironment('PRINT_SENSORY_WIRE')) {
      // Used by the server contract test to verify an actual Flutter payload.
      // ignore: avoid_print
      print('SENSORY_FLUTTER_WIRE=${jsonEncode(payload)}');
    }
  });
}
