import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/sensory/revisit_intent.dart';
import 'package:soolgyul/src/core/sensory/sensory_meanings.dart';
import 'package:soolgyul/src/core/sensory/sensory_question_flow.dart';

import '../support/sensory_fixtures.dart';

void main() {
  final vocabulary = serviceVocabulary();
  final registry = SensoryMeaningRegistry(vocabulary: vocabulary);
  final redWine = gaugesFor('wine', 'red_wine');

  test('the aromas offered are the dictionary\'s aroma descriptors, each '
      'under its own word', () {
    final aroma = {
      for (final group in vocabulary['groups'] as List)
        if (group['domain'] == 'descriptor' &&
            (group['phases'] as List).contains('aroma'))
          group['key'] as String: group['label_ko'] as String,
    };
    expect(registry.aromaKeys, aroma.keys.toSet());
    // A fruit, a wood note, a smoke note, a flower and a Korean term.
    for (final key in ['cherry', 'vanilla', 'smoke', 'jasmine', 'nuruk']) {
      expect(registry.aromaLabel(key), aroma[key]);
    }
    expect(registry.aromaLabel('invented'), isNull);
    expect(
      () => SensoryMeaningRegistry(vocabulary: {'groups': <Object?>[]}),
      throwsFormatException,
    );
  });

  test('a flow reads into the stored option keys by question, and nothing '
      'left empty is filled in', () {
    final flow = registry.createFlow(redWine);
    expect(registry.readAnswers(flow), {
      for (final key in SensoryQuestionKeys.all) key: isEmpty,
    });

    flow.setRevisit(RevisitIntent.wouldAcceptAgain);
    flow.toggleAroma(AromaStage.nose, 'cherry');
    flow.chooseLevel('tannin', 5);
    flow.toggleBurden(const SensoryAnswerItem.level('tannin'));
    flow.toggleAroma(AromaStage.finish, 'smoke');
    expect(registry.readAnswers(flow), {
      'sensory_revisit': ['revisit:wouldAcceptAgain'],
      'sensory_nose_aroma': ['aroma:nose:cherry:liked'],
      'sensory_palate_level': ['level:tannin:5:disliked'],
      'sensory_palate_aroma': isEmpty,
      'sensory_finish_level': isEmpty,
      'sensory_finish_aroma': ['aroma:finish:smoke:liked'],
    });

    // A changed answer leaves nothing of the old one behind.
    flow.chooseLevel('tannin', 2);
    flow.skipNose();
    final changed = registry.readAnswers(flow);
    expect(changed['sensory_nose_aroma'], ['nose:unsure']);
    expect(changed['sensory_palate_level'], ['level:tannin:2:liked']);
  });

  test('stored answers are marked in a flow again; an aroma no longer '
      'offered and a gauge the kind is not asked are left out', () {
    final stored = [
      'revisit:doNotWantAgain',
      'aroma:nose:cherry:disliked',
      'aroma:palate:vanilla:liked',
      'level:sweetness:2:liked',
      'level:tannin:4:disliked',
      'level:finish_length:5:liked',
      'aroma:finish:smoke:disliked',
      // What this app cannot place.
      'aroma:nose:retired_aroma:liked',
      'level:peat:4:liked',
      'level:sweetness:9:liked',
      'reaction:taste:sweetness:liked',
    ];
    final flow = registry.createFlow(redWine, only: SensoryPart.palate);
    registry.restoreAnswers(flow, stored);
    expect(flow.revisit, RevisitIntent.doNotWantAgain);
    expect(registry.readAnswers(flow), {
      'sensory_revisit': ['revisit:doNotWantAgain'],
      'sensory_nose_aroma': ['aroma:nose:cherry:disliked'],
      'sensory_palate_level': [
        'level:sweetness:2:liked',
        'level:tannin:4:disliked',
      ],
      'sensory_palate_aroma': ['aroma:palate:vanilla:liked'],
      'sensory_finish_level': ['level:finish_length:5:liked'],
      'sensory_finish_aroma': ['aroma:finish:smoke:disliked'],
    });

    final skipped = registry.createFlow(redWine);
    registry.restoreAnswers(skipped, ['nose:unsure']);
    expect(skipped.noseSkipped, isTrue);
    expect(SensoryQuestionKeys.of(SensoryPart.palate), [
      'sensory_palate_level',
      'sensory_palate_aroma',
    ]);
  });
}
