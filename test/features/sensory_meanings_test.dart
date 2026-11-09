import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/onboarding/revisit_intent.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/finish_choices.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/sensory_meanings.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/sensory_option_definitions.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/sensory_question_flow.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/taste_reactions.dart';
import 'package:soolgyul/src/features/onboarding/data/dictionary_views.dart';

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  late Map<String, dynamic> vocabulary;
  late Map<String, dynamic> bank;
  late SensoryMeaningRegistry registry;
  late SensoryOptionDefinitions definitions;
  // A sample stands in for the whole aroma dictionary: a fruit, a wood note,
  // a smoke note, a flower and a search-only Korean term.
  const sampleAromaKeys = {'cherry', 'vanilla', 'smoke', 'jasmine', 'nuruk'};
  setUp(() {
    vocabulary = serviceVocabularyView(
      readJson('catalog/dictionary/terms.json'),
    );
    bank = readJson('catalog/sensory/palate-question-bank.json');
    definitions = SensoryOptionDefinitions.fromJson(
      readJson('catalog/sensory/answer-option-definitions.json'),
    );
    registry = SensoryMeaningRegistry(
      vocabulary: vocabulary,
      tasteBank: bank,
      definitions: definitions,
    );
  });

  test('current and saved option IDs keep exactly one meaning', () {
    final expected = <String>{};
    final aroma = (vocabulary['groups'] as List)
        .where(
          (g) =>
              g['domain'] == 'descriptor' &&
              (g['phases'] as List).contains('aroma'),
        )
        .map((g) => g['key'] as String)
        .toSet();
    expect(registry.aromaKeys, aroma);
    for (final section in SensorySection.values) {
      final keys = switch (section) {
        SensorySection.aroma => aroma,
        SensorySection.taste => SensoryQuestionFlow.tasteKeys,
        SensorySection.mouthfeel => SensoryQuestionFlow.mouthfeelKeys,
      };
      for (final key in keys) {
        if (section != SensorySection.taste) {
          expected.add('notice:${section.name}:$key');
        }
        if (section != SensorySection.aroma) {
          expected.add('reaction:${section.name}:$key:fine');
        }
        for (final side in TasteReaction.sides) {
          expected.add('reaction:${section.name}:$key:${side.name}');
          if (section != SensorySection.mouthfeel) {
            expected.add('target:${section.name}:$key:${side.name}');
            final reasons = section == SensorySection.aroma
                ? definitions.reasons[side]!.keys
                : ((bank['entries'] as List).singleWhere(
                            (e) => e['key'] == key,
                          )[side == TasteReaction.liked
                              ? 'positive_reasons'
                              : 'negative_reasons']
                          as List)
                      .map((r) => r['key'] as String);
            for (final reason in reasons) {
              expected.add('reason:${section.name}:$key:${side.name}:$reason');
            }
          }
        }
      }
    }
    expected.addAll(RevisitIntent.values.map((i) => 'revisit:${i.name}'));
    expected.addAll(FinishOption.values.map((o) => 'finish:${o.name}'));
    for (final section in ['aroma', 'mouthfeel', 'finish']) {
      expected.add('$section:unsure');
    }
    expect(registry.entries.keys.toSet(), expected);
    expect(
      definitions.mouthfeel.keys.toSet(),
      SensoryQuestionFlow.mouthfeelKeys,
    );
  });

  test('shared option definitions reject invalid data and are immutable', () {
    Map<String, dynamic> fresh() =>
        readJson('catalog/sensory/answer-option-definitions.json');
    final invalidMeaning = fresh();
    invalidMeaning['reasons']['liked'][0]['meaning'] = 'invented';
    expect(
      () => SensoryOptionDefinitions.fromJson(invalidMeaning),
      throwsFormatException,
    );

    final duplicateReason = fresh();
    duplicateReason['reasons']['liked'][1] =
        duplicateReason['reasons']['liked'][0];
    expect(
      () => SensoryOptionDefinitions.fromJson(duplicateReason),
      throwsFormatException,
    );

    final emptyLabel = fresh();
    emptyLabel['mouthfeel'][0]['label_ko'] = ' ';
    expect(
      () => SensoryOptionDefinitions.fromJson(emptyLabel),
      throwsFormatException,
    );

    final invalidMouthfeel = fresh();
    invalidMouthfeel['mouthfeel'][0]['key'] = 'invented';
    expect(
      () => SensoryMeaningRegistry(
        vocabulary: vocabulary,
        tasteBank: bank,
        definitions: SensoryOptionDefinitions.fromJson(invalidMouthfeel),
      ),
      throwsFormatException,
    );

    final source = fresh();
    final parsed = SensoryOptionDefinitions.fromJson(source);
    source['reasons']['disliked'][3]['taste_meanings'] = {
      'bitterness': 'unknown',
    };
    expect(
      parsed.reasons[TasteReaction.disliked]!['disharmony']!.meaningForTaste(
        'bitterness',
      ),
      AnswerMeaning.masksOtherSensations,
    );
    expect(() => parsed.reasons.clear(), throwsUnsupportedError);
    expect(
      () => parsed.reasons[TasteReaction.liked]!.clear(),
      throwsUnsupportedError,
    );
    expect(() => parsed.mouthfeel.clear(), throwsUnsupportedError);
  });

  test(
    'reasons are the three intensity or harmony choices per side; the retired ones are gone',
    () {
      for (final section in [SensorySection.aroma, SensorySection.taste]) {
        final keys = section == SensorySection.aroma
            ? sampleAromaKeys
            : SensoryQuestionFlow.tasteKeys;
        for (final key in keys) {
          expect(registry.reasonKeys(section, key, TasteReaction.liked), {
            'gentle',
            'pronounced',
            'harmony',
          });
          expect(registry.reasonKeys(section, key, TasteReaction.disliked), {
            'too_strong',
            'too_weak',
            'disharmony',
          });
          // 이유는 잘 모르겠어요 is retired but stays readable; the character
          // reason (맛 자체가 좋았어요 · 취향이 아니었어요) is gone for good.
          expect(
            registry
                .lookup('reason:${section.name}:$key:liked:unspecified')
                .meaning,
            AnswerMeaning.reasonUnknown,
          );
          for (final side in TasteReaction.sides) {
            expect(
              () => registry.lookup(
                'reason:${section.name}:$key:${side.name}:character',
              ),
              throwsArgumentError,
            );
          }
          // Only tastes still take reasons.
          if (section != SensorySection.taste) continue;
          final flow = registry.createFlow();
          flow.toggleReaction(section, key, TasteReaction.liked);
          for (final retired in ['character', 'unspecified']) {
            expect(
              () => flow.toggleReason(section, key, retired),
              throwsArgumentError,
            );
          }
          expect(flow.reactions(section)[key], TasteReaction.liked);
          expect(flow.reasons(section, key), isEmpty);
          flow.toggleReason(section, key, 'gentle');
          final current = registry.readAnswers(flow);
          expect(
            current.any(
              (meaning) =>
                  meaning.meaning == AnswerMeaning.gentleIntensityAccepted,
            ),
            isTrue,
          );
          flow.toggleReaction(section, key, TasteReaction.disliked);
          flow.toggleReason(section, key, 'too_strong');
          expect(
            registry
                .readAnswers(flow)
                .any(
                  (meaning) =>
                      meaning.id ==
                      'reason:${section.name}:$key:disliked:too_strong',
                ),
            isTrue,
          );
        }
      }
    },
  );

  test(
    'aroma choices including search-only terms accept both reactions; stored reasons stay readable',
    () {
      expect(registry.aromaKeys, containsAll(sampleAromaKeys));
      for (final key in sampleAromaKeys) {
        for (final side in TasteReaction.sides) {
          final flow = registry.createFlow();
          flow.toggleNotice(SensorySection.aroma, key);
          flow.toggleReaction(SensorySection.aroma, key, side);
          expect(
            registry
                .readAnswers(flow)
                .any((m) => m.id == 'reaction:aroma:$key:${side.name}'),
            true,
          );
          // No aroma reason page any more; answers saved earlier still read.
          expect(
            flow.steps.map((step) => step.key),
            isNot(contains(startsWith('reason:aroma'))),
          );
          for (final reason in registry.reasonKeys(
            SensorySection.aroma,
            key,
            side,
          )) {
            expect(
              registry.lookup('reason:aroma:$key:${side.name}:$reason').subject,
              key,
            );
          }
        }
      }
    },
  );

  test(
    'all selectable taste reasons preserve target, polarity and declared meaning',
    () {
      for (final entry in bank['entries'] as List) {
        for (final side in TasteReaction.sides) {
          final key = entry['key'] as String;
          for (final reason in registry.reasonKeys(
            SensorySection.taste,
            key,
            side,
          )) {
            final flow = registry.createFlow();
            flow.toggleReaction(SensorySection.taste, key, side);
            flow.toggleReason(SensorySection.taste, key, reason);
            final meaning = registry
                .readAnswers(flow)
                .singleWhere((m) => m.id.startsWith('reason:'));
            expect(meaning.subject, key);
            expect(meaning.reaction, side);
            expect(meaning.phase, AnswerPhase.duringDrinking);
          }
        }
      }
      expect(
        registry.lookup('reason:taste:bitterness:disliked:disharmony').meaning,
        AnswerMeaning.masksOtherSensations,
      );
      expect(
        registry.lookup('reason:taste:sweetness:disliked:disharmony').meaning,
        AnswerMeaning.masksOtherSensations,
      );
      expect(
        registry.lookup('reason:taste:acidity:disliked:too_weak').meaning,
        AnswerMeaning.wantsMoreIntensity,
      );
      expect(
        registry.lookup('reason:taste:acidity:liked:pronounced').meaning,
        AnswerMeaning.distinctIntensityAccepted,
      );
    },
  );

  test(
    'mere aroma selection never becomes liking, ingredients or sweetness',
    () {
      final flow = registry.createFlow();
      flow.toggleNotice(SensorySection.aroma, 'vanilla');
      final facts = registry.readAnswers(flow);
      expect(facts.length, 1);
      expect(facts.single.meaning, AnswerMeaning.noticed);
      expect(facts.single.reaction, isNull);
      expect(facts.single.subject, 'vanilla');
    },
  );

  test('mouthfeel and finish stay separate; every finish carries its side', () {
    final flow = registry.createFlow();
    flow.toggleNotice(SensorySection.mouthfeel, 'heavy');
    flow.toggleReaction(SensorySection.mouthfeel, 'heavy', TasteReaction.liked);
    flow.finish.toggle(FinishOption.heavy);
    final facts = registry.readAnswers(flow);
    expect(
      facts.singleWhere((m) => m.id == 'reaction:mouthfeel:heavy:liked').phase,
      AnswerPhase.duringDrinking,
    );
    final after = facts.singleWhere((m) => m.id == 'finish:heavy');
    expect(after.phase, AnswerPhase.afterSwallowing);
    expect(after.reaction, TasteReaction.disliked);
    expect(registry.lookup('finish:tooShort').reaction, TasteReaction.disliked);
    expect(registry.lookup('finish:aromaEcho').reaction, TasteReaction.liked);
    expect(
      registry.lookup('finish:offFlavor').reaction,
      TasteReaction.disliked,
    );
    expect(
      registry.reasonKeys(
        SensorySection.mouthfeel,
        'heavy',
        TasteReaction.liked,
      ),
      isEmpty,
    );
  });

  test('unknown, 적당했어요 and missing are not dislike', () {
    final flow = registry.createFlow();
    expect(registry.readAnswers(flow), isEmpty);
    flow.setUnsure(SensorySection.aroma);
    flow.toggleReaction(SensorySection.taste, 'sweetness', TasteReaction.fine);
    final facts = registry.readAnswers(flow);
    expect(facts.map((m) => m.meaning).toSet(), {
      AnswerMeaning.unknown,
      AnswerMeaning.balanced,
    });
    expect(facts.any((m) => m.reaction == TasteReaction.disliked), false);
    expect(() => flow.setUnsure(SensorySection.taste), throwsArgumentError);
  });

  test(
    'editing parent removes stale facts and a reaction without reasons stands alone',
    () {
      final flow = registry.createFlow();
      flow.toggleReaction(SensorySection.taste, 'acidity', TasteReaction.liked);
      flow.toggleReason(SensorySection.taste, 'acidity', 'harmony');
      expect(
        registry
            .readAnswers(flow)
            .any((m) => m.meaning == AnswerMeaning.harmonious),
        true,
      );
      flow.toggleReaction(
        SensorySection.taste,
        'acidity',
        TasteReaction.disliked,
      );
      final facts = registry.readAnswers(flow);
      expect(facts.length, 1);
      expect(facts.single.reaction, TasteReaction.disliked);
    },
  );

  test(
    'no target is recorded; reasons on two liked tastes keep their own subject',
    () {
      final flow = registry.createFlow();
      flow.toggleReaction(SensorySection.taste, 'acidity', TasteReaction.liked);
      flow.toggleReaction(
        SensorySection.taste,
        'sweetness',
        TasteReaction.liked,
      );
      flow.toggleReason(SensorySection.taste, 'acidity', 'pronounced');
      flow.toggleReason(SensorySection.taste, 'sweetness', 'gentle');
      final facts = registry.readAnswers(flow);
      expect(
        facts.any((m) => m.meaning == AnswerMeaning.reasonTargetSelected),
        false,
      );
      expect(
        facts
            .where((m) => m.id.startsWith('reason:'))
            .map((m) => (m.subject, m.meaning)),
        [
          ('acidity', AnswerMeaning.distinctIntensityAccepted),
          ('sweetness', AnswerMeaning.gentleIntensityAccepted),
        ],
      );
      // Saved targets still read.
      expect(
        registry.lookup('target:taste:acidity:liked').meaning,
        AnswerMeaning.reasonTargetSelected,
      );
    },
  );

  test(
    'invalid vocabulary, unknown reasons and hidden/legacy keys fail closed',
    () {
      expect(
        () => registry.lookup('notice:aroma:invented'),
        throwsArgumentError,
      );
      expect(
        () => registry.lookup('reason:mouthfeel:heavy:liked:gentle'),
        throwsArgumentError,
      );
      final entry = (bank['entries'] as List).first as Map;
      (entry['positive_reasons'] as List).first['key'] = 'unmapped';
      expect(
        () => SensoryMeaningRegistry(
          vocabulary: vocabulary,
          tasteBank: bank,
          definitions: definitions,
        ),
        throwsFormatException,
      );
    },
  );
}
