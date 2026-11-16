import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/core/sensory/revisit_intent.dart';
import 'package:soolgyul/src/core/sensory/sensory_meanings.dart';
import 'package:soolgyul/src/core/sensory/sensory_question_flow.dart';
import 'package:soolgyul/src/features/taste_card/data/sensory_submission.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_submission_mapper.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';

import '../support/sensory_fixtures.dart';

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

  // A drink of no known kind is asked the three gauges of a wine.
  SensoryQuestionFlow newFlow() => registry.createFlow(gaugesFor(null));

  setUp(() {
    registry = sensoryRegistry();
    flow = newFlow()..setRevisit(RevisitIntent.wantAgain);
  });

  CreateTasteCardResultRequest submit({
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

  QuestionnaireAnswerInput answer(String key) =>
      submit().answers.singleWhere((answer) => answer.questionKey == key);

  test('the app\'s submission is the wire the server is tested with', () {
    for (final key in ['apple', 'pear']) {
      flow.toggleAroma(AromaStage.nose, key);
    }
    flow.chooseLevel('sweetness', 2);
    flow.chooseLevel('acidity', 4);
    flow.toggleAroma(AromaStage.palate, 'vanilla');
    flow.chooseLevel('finish_length', 4);
    flow.chooseLevel('finish_character', 3);
    flow.toggleAroma(AromaStage.finish, 'smoke');
    // What the review page marks as a burden.
    flow.toggleBurden(const SensoryAnswerItem.level('acidity'));
    flow.toggleBurden(
      const SensoryAnswerItem.aroma(AromaStage.finish, 'smoke'),
    );

    final payload = TasteCardSubmissionMapper.fromSensoryFlow(
      idempotencyKey: '10000000-0000-4000-8000-000000000001',
      anonymousSessionId: 'sensory-test',
      selection: _namedDrink,
      flow: flow,
      registry: registry,
    ).toJson();
    expect(payload['questionnaire_version'], 'sensory-questionnaire-v2');
    expect(
      (payload['answers'] as List).map((row) => row['question_key']),
      SensorySubmission.questionKeys,
    );
    // The Deno suite checks that the server accepts this same file.
    final sharedFixture = jsonDecode(
      File(
        'supabase/functions/_tests/fixtures/sensory_flutter_wire_v2.json',
      ).readAsStringSync(),
    );
    expect(payload, sharedFixture);
  });

  test('only answered questions are sent: nothing left empty becomes '
      'unknown, absence, neutral or dislike', () {
    final request = submit();
    expect(request.answers, hasLength(1));
    expect(request.answers.single.questionKey, 'sensory_revisit');
    expect(request.answers.single.selectedOptionKeys, ['revisit:wantAgain']);
    expect(request.q7FreeText, isNull);
    expect(request.photoAssetId, isNull);

    flow.chooseLevel('body', 3);
    expect(submit().answers.map((answer) => answer.toJson()), [
      {
        'question_key': 'sensory_revisit',
        'selected_option_keys': ['revisit:wantAgain'],
        'free_text': null,
      },
      {
        'question_key': 'sensory_palate_level',
        'selected_option_keys': ['level:body:3:liked'],
        'free_text': null,
      },
    ]);
  });

  test('a skipped nose is sent as its own answer, and a pick replaces it', () {
    flow.skipNose();
    expect(answer('sensory_nose_aroma').selectedOptionKeys, ['nose:unsure']);
    flow.toggleAroma(AromaStage.nose, 'apple');
    expect(answer('sensory_nose_aroma').selectedOptionKeys, [
      'aroma:nose:apple:liked',
    ]);
  });

  test(
    'request snapshots are detached from later answer edits and immutable',
    () {
      flow.toggleAroma(AromaStage.nose, 'vanilla');
      final request = submit();
      final before = jsonEncode(request.toJson());
      flow.skipNose();
      expect(jsonEncode(request.toJson()), before);
      expect(() => request.answers.clear(), throwsUnsupportedError);
      expect(
        () => request.answers.last.selectedOptionKeys.clear(),
        throwsUnsupportedError,
      );
      expect(answer('sensory_nose_aroma').selectedOptionKeys, ['nose:unsure']);
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
      expect(anonymous.anonymousSessionId, 'session');
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
    },
  );

  test('required answers and drink name fail closed before submission', () {
    expect(() => submit(selectedFlow: newFlow()), throwsStateError);
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
}
