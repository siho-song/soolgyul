import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/sensory/revisit_intent.dart';
import 'package:soolgyul/src/core/sensory/finish_choices.dart';
import 'package:soolgyul/src/core/sensory/sensory_asked_keys.dart';
import 'package:soolgyul/src/core/sensory/sensory_question_flow.dart';
import 'package:soolgyul/src/core/sensory/taste_reactions.dart';

void main() {
  SensoryQuestionFlow create() => SensoryQuestionFlow(
    aromaKeys: {'cherry', 'oak', 'apple', 'pear', 'mint', 'rose'},
    reasonKeys: (section, _, side) => section == SensorySection.mouthfeel
        ? <String>{}
        : side == TasteReaction.liked
        ? {'gentle', 'pronounced', 'harmony'}
        : {'too_strong', 'too_weak', 'disharmony'},
  );
  test(
    'unknown observations skip follow-ups and finish reaches completion',
    () {
      final flow = create();
      expect(flow.next, throwsStateError);
      flow.setRevisit(RevisitIntent.unsure);
      flow.next();
      expect(flow.current.section, SensorySection.aroma);
      flow.setUnsure(SensorySection.aroma);
      flow.next();
      expect(flow.current.section, SensorySection.taste);
      // Tastes cannot be skipped: every taste asked needs an answer.
      expect(() => flow.setUnsure(SensorySection.taste), throwsArgumentError);
      expect(flow.canContinue, isFalse);
      for (final key in flow.askedTasteKeys) {
        flow.toggleReaction(SensorySection.taste, key, TasteReaction.fine);
      }
      flow.next();
      expect(flow.current.section, SensorySection.mouthfeel);
      flow.setUnsure(SensorySection.mouthfeel);
      flow.next();
      expect(flow.current.page, SensoryPage.finish);
      flow.finish.toggle(FinishOption.clean);
      flow.next();
      expect(flow.current.page, SensoryPage.complete);
      flow.back();
      expect(flow.finish.selected, {FinishOption.clean});
    },
  );

  test('the full path has one page per section and no reason pages', () {
    final flow = create();
    flow.setRevisit(RevisitIntent.wantAgain);
    flow.toggleNotice(SensorySection.aroma, 'cherry');
    flow.toggleReaction(SensorySection.aroma, 'cherry', TasteReaction.liked);
    for (final key in ['sweetness', 'acidity']) {
      flow.toggleReaction(SensorySection.taste, key, TasteReaction.liked);
    }
    flow.toggleReason(SensorySection.taste, 'acidity', 'harmony');
    flow.toggleReason(SensorySection.taste, 'sweetness', 'gentle');
    flow.toggleReaction(
      SensorySection.taste,
      'bitterness',
      TasteReaction.disliked,
    );
    flow.toggleReason(SensorySection.taste, 'bitterness', 'too_strong');
    flow.toggleNotice(SensorySection.mouthfeel, 'heavy');
    flow.toggleReaction(
      SensorySection.mouthfeel,
      'heavy',
      TasteReaction.disliked,
    );
    final visited = <String>[];
    while (flow.current.page != SensoryPage.complete) {
      visited.add(flow.current.key);
      flow.next();
      expect(visited.length, lessThan(20));
    }
    expect(visited, [
      'revisit:',
      'notice:aroma',
      'reaction:taste',
      'reaction:mouthfeel',
      'finish:',
    ]);
  });

  test(
    'one tap likes an aroma, a second makes it a burden, a third clears',
    () {
      final flow = create();
      flow.setRevisit(RevisitIntent.wantAgain);
      flow.cycleAroma('cherry');
      expect(flow.selected(SensorySection.aroma), {'cherry'});
      expect(flow.reactions(SensorySection.aroma), {
        'cherry': TasteReaction.liked,
      });
      flow.cycleAroma('cherry');
      expect(flow.reactions(SensorySection.aroma), {
        'cherry': TasteReaction.disliked,
      });
      flow.cycleAroma('cherry');
      expect(flow.selected(SensorySection.aroma), isEmpty);
      expect(flow.reactions(SensorySection.aroma), isEmpty);
      expect(
        flow.steps.map((step) => step.key),
        isNot(contains('reaction:aroma')),
      );
    },
  );

  test('removing an observation clears only its descendants', () {
    final flow = create();
    flow.setRevisit(RevisitIntent.wantAgain);
    flow.toggleNotice(SensorySection.aroma, 'cherry');
    flow.toggleReaction(SensorySection.aroma, 'cherry', TasteReaction.liked);
    flow.toggleReaction(SensorySection.taste, 'sweetness', TasteReaction.liked);
    flow.toggleReason(SensorySection.taste, 'sweetness', 'harmony');
    flow.finish.toggle(FinishOption.clean);
    flow.toggleNotice(SensorySection.aroma, 'cherry');
    expect(flow.reactions(SensorySection.aroma), isEmpty);
    expect(flow.reasons(SensorySection.taste, 'sweetness'), {'harmony'});
    expect(flow.finish.selected, {FinishOption.clean});
  });

  test('reasons belong to one reaction and go with it', () {
    final flow = create();
    flow.toggleReaction(SensorySection.taste, 'sweetness', TasteReaction.liked);
    flow.toggleReaction(SensorySection.taste, 'acidity', TasteReaction.liked);
    flow.toggleReason(SensorySection.taste, 'sweetness', 'gentle');
    flow.toggleReason(SensorySection.taste, 'acidity', 'harmony');
    expect(flow.reasons(SensorySection.taste, 'sweetness'), {'gentle'});
    expect(flow.reasons(SensorySection.taste, 'acidity'), {'harmony'});
    // Flipping the reaction drops its reasons; the other taste keeps its own.
    flow.toggleReaction(
      SensorySection.taste,
      'sweetness',
      TasteReaction.disliked,
    );
    expect(flow.reasons(SensorySection.taste, 'sweetness'), isEmpty);
    expect(flow.reasons(SensorySection.taste, 'acidity'), {'harmony'});
    // Tapping the same reaction again clears it, reasons included.
    flow.toggleReason(SensorySection.taste, 'sweetness', 'too_strong');
    flow.toggleReaction(
      SensorySection.taste,
      'sweetness',
      TasteReaction.disliked,
    );
    expect(
      flow.reactions(SensorySection.taste).containsKey('sweetness'),
      false,
    );
    expect(flow.reasons(SensorySection.taste, 'sweetness'), isEmpty);
  });

  test('aromas take no reason, whatever the revisit answer', () {
    final flow = create();
    flow.setRevisit(RevisitIntent.wantAgain);
    for (final key in ['cherry', 'oak']) {
      flow.toggleNotice(SensorySection.aroma, key);
    }
    flow.toggleReaction(SensorySection.aroma, 'cherry', TasteReaction.liked);
    flow.toggleReaction(SensorySection.aroma, 'oak', TasteReaction.disliked);
    flow.setRevisit(RevisitIntent.doNotWantAgain);
    expect(
      () => flow.toggleReason(SensorySection.aroma, 'oak', 'too_strong'),
      throwsArgumentError,
    );
    expect(flow.reasons(SensorySection.aroma, 'oak'), isEmpty);
  });

  test(
    'aroma limit, unknown exclusivity, reason validation and multi-select',
    () {
      final flow = create();
      for (final key in ['cherry', 'oak', 'apple', 'pear', 'mint']) {
        flow.toggleNotice(SensorySection.aroma, key);
      }
      expect(
        () => flow.toggleNotice(SensorySection.aroma, 'rose'),
        throwsStateError,
      );
      flow.setUnsure(SensorySection.aroma);
      flow.toggleNotice(SensorySection.aroma, 'oak');
      expect(flow.unsure(SensorySection.aroma), false);
      // No reason before a side is taken, and none for 적당했어요.
      expect(
        () =>
            flow.toggleReason(SensorySection.taste, 'bitterness', 'too_strong'),
        throwsArgumentError,
      );
      flow.toggleReaction(
        SensorySection.taste,
        'bitterness',
        TasteReaction.fine,
      );
      expect(
        () =>
            flow.toggleReason(SensorySection.taste, 'bitterness', 'too_strong'),
        throwsArgumentError,
      );
      flow.toggleReaction(
        SensorySection.taste,
        'bitterness',
        TasteReaction.disliked,
      );
      flow.toggleReason(SensorySection.taste, 'bitterness', 'too_strong');
      flow.toggleReason(SensorySection.taste, 'bitterness', 'disharmony');
      expect(flow.reasons(SensorySection.taste, 'bitterness').length, 2);
      flow.toggleReason(SensorySection.taste, 'bitterness', 'too_strong');
      expect(flow.reasons(SensorySection.taste, 'bitterness'), {'disharmony'});
      expect(
        () => flow.toggleReason(SensorySection.taste, 'bitterness', 'invented'),
        throwsArgumentError,
      );
      // A reason from the other side is not this reaction's.
      expect(
        () => flow.toggleReason(SensorySection.taste, 'bitterness', 'gentle'),
        throwsArgumentError,
      );
    },
  );

  test(
    'a mouthfeel axis takes one answer; the same answer again clears it',
    () {
      final flow = create();
      flow.chooseMouthfeel('light', TasteReaction.liked);
      expect(flow.selected(SensorySection.mouthfeel), {'light'});
      expect(flow.reactions(SensorySection.mouthfeel), {
        'light': TasteReaction.liked,
      });
      // The other end of the axis replaces it; 적당했어요 sits on that end.
      flow.chooseMouthfeel('heavy', TasteReaction.fine);
      expect(flow.selected(SensorySection.mouthfeel), {'heavy'});
      expect(flow.reactions(SensorySection.mouthfeel), {
        'heavy': TasteReaction.fine,
      });
      // Another axis is independent.
      flow.chooseMouthfeel('warmth', TasteReaction.disliked);
      expect(flow.reactions(SensorySection.mouthfeel).length, 2);
      flow.chooseMouthfeel('heavy', TasteReaction.fine);
      expect(flow.reactions(SensorySection.mouthfeel), {
        'warmth': TasteReaction.disliked,
      });
      expect(flow.selected(SensorySection.mouthfeel), {'warmth'});
      expect(
        () => flow.chooseMouthfeel('sweetness', TasteReaction.liked),
        throwsArgumentError,
      );
    },
  );

  test('a judgement on a two-ended axis waits for its end before 다음', () {
    final flow = create();
    flow.setRevisit(RevisitIntent.wantAgain);
    flow.setUnsure(SensorySection.aroma);
    for (final key in flow.askedTasteKeys) {
      flow.toggleReaction(SensorySection.taste, key, TasteReaction.fine);
    }
    while (flow.current.key != 'reaction:mouthfeel') {
      flow.next();
    }
    const weight = ['light', 'heavy'];
    expect(flow.canContinue, isTrue);
    flow.judgeMouthfeel(weight, TasteReaction.liked);
    expect(flow.mouthfeelJudgement(weight), TasteReaction.liked);
    expect(flow.reactions(SensorySection.mouthfeel), isEmpty);
    expect(flow.canContinue, isFalse);
    flow.chooseMouthfeel('heavy', TasteReaction.liked);
    expect(flow.canContinue, isTrue);
    expect(flow.reactions(SensorySection.mouthfeel), {
      'heavy': TasteReaction.liked,
    });
    // The same judgement again clears the axis; 적당했어요 stores at once.
    flow.judgeMouthfeel(weight, TasteReaction.liked);
    expect(flow.mouthfeelJudgement(weight), isNull);
    flow.judgeMouthfeel(weight, TasteReaction.fine);
    expect(flow.reactions(SensorySection.mouthfeel), {
      'heavy': TasteReaction.fine,
    });
    // A single sensation needs no end.
    flow.judgeMouthfeel(const ['warmth'], TasteReaction.disliked);
    expect(
      flow.reactions(SensorySection.mouthfeel)['warmth'],
      TasteReaction.disliked,
    );
    // SKIP clears a waiting judgement too.
    flow.judgeMouthfeel(const ['smooth', 'drying'], TasteReaction.disliked);
    expect(flow.canContinue, isFalse);
    flow.setUnsure(SensorySection.mouthfeel);
    expect(flow.canContinue, isTrue);
    expect(flow.mouthfeelJudgement(const ['smooth', 'drying']), isNull);
    for (final keys in [
      const ['sweetness'],
      const ['light', 'warmth'],
      const <String>[],
    ]) {
      expect(
        () => flow.judgeMouthfeel(keys, TasteReaction.liked),
        throwsArgumentError,
      );
    }
  });

  test('mouthfeel reactions lead straight to finish without reasons', () {
    final flow = create();
    flow.chooseMouthfeel('heavy', TasteReaction.disliked);
    flow.chooseMouthfeel('smooth', TasteReaction.liked);
    expect(flow.reactions(SensorySection.mouthfeel).length, 2);
    expect(
      () => flow.toggleReason(SensorySection.mouthfeel, 'heavy', 'too_strong'),
      throwsArgumentError,
    );
    flow.setRevisit(RevisitIntent.wantAgain);
    for (final key in flow.askedTasteKeys) {
      flow.toggleReaction(SensorySection.taste, key, TasteReaction.fine);
    }
    while (flow.current.key != 'reaction:mouthfeel') {
      flow.next();
    }
    flow.next();
    expect(flow.current.page, SensoryPage.finish);
    flow.back();
    expect(flow.current.key, 'reaction:mouthfeel');
    expect(flow.reactions(SensorySection.mouthfeel).length, 2);
  });

  test('finish is multi-select; unsure is exclusive and toggles off', () {
    final state = FinishSelection();
    state.toggle(FinishOption.aromaEcho);
    state.toggle(FinishOption.offFlavor);
    expect(state.selected.length, 2);
    state.toggleUnsure();
    expect(state.selected, isEmpty);
    state.toggle(FinishOption.heavy);
    expect(state.unsure, false);
    state.toggle(FinishOption.heavy);
    expect(state.selected, isEmpty);
    state.toggleUnsure();
    state.toggleUnsure();
    expect(state.unsure, false);
  });

  group('asked keys per kind', () {
    void expectAsked(
      String category,
      String? style,
      List<String> tastes,
      List<String> mouthfeel,
    ) {
      final asked = SensoryAskedKeys.forProduct(category, style);
      expect(asked.tasteKeys.toList(), tastes, reason: '$category/$style');
      expect(
        asked.mouthfeelKeys.toList(),
        mouthfeel,
        reason: '$category/$style',
      );
    }

    test('wines are asked sweetness and acidity, tannin only where there is '
        'some, and the mousse only for sparkling', () {
      expectAsked(
        'wine',
        'red_wine',
        ['sweetness', 'acidity'],
        ['light', 'heavy', 'smooth', 'drying', 'warmth'],
      );
      expectAsked(
        'wine',
        'white_wine',
        ['sweetness', 'acidity'],
        ['light', 'heavy', 'warmth'],
      );
      expectAsked(
        'wine',
        'sparkling_wine',
        ['sweetness', 'acidity'],
        ['light', 'heavy', 'bubbles', 'warmth'],
      );
      expectAsked(
        'wine',
        'vermouth',
        ['sweetness', 'acidity', 'bitterness'],
        ['light', 'heavy', 'warmth'],
      );
    });

    test('whisky is not asked acidity, and no still kind is asked 탄산', () {
      const still = ['light', 'heavy', 'smooth', 'drying', 'warmth'];
      expectAsked('whisky', null, ['sweetness', 'bitterness'], still);
      expectAsked('whisky', 'blended_whisky', [
        'sweetness',
        'bitterness',
      ], still);
      for (final style in [null, 'junmai', 'daiginjo']) {
        expectAsked(
          'sake',
          style,
          SensoryQuestionFlow.tasteKeys.toList(),
          still,
        );
      }
      for (final style in ['distilled_soju', 'yakju', 'korean_cheongju']) {
        expectAsked(
          'korean_traditional',
          style,
          SensoryQuestionFlow.tasteKeys.toList(),
          still,
        );
      }
    });

    test('탁주, a traditional bottle of unknown kind and drinks without a '
        'product keep every choice', () {
      for (final style in [null, 'takju']) {
        final asked = SensoryAskedKeys.forProduct('korean_traditional', style);
        expect(asked.tasteKeys, SensoryQuestionFlow.tasteKeys);
        expect(asked.mouthfeelKeys, SensoryQuestionFlow.mouthfeelKeys);
      }
      expect(SensoryAskedKeys.all.mouthfeelKeys, contains('bubbles'));
    });

    test('the flow refuses answers its kind is not asked', () {
      final asked = SensoryAskedKeys.forProduct('wine', 'white_wine');
      final flow = SensoryQuestionFlow(
        aromaKeys: {'apple'},
        reasonKeys: (_, _, _) => {'unspecified'},
        askedTasteKeys: asked.tasteKeys,
        askedMouthfeelKeys: asked.mouthfeelKeys,
      );
      expect(
        () => flow.toggleReaction(
          SensorySection.taste,
          'bitterness',
          TasteReaction.disliked,
        ),
        throwsArgumentError,
      );
      expect(
        () => flow.toggleNotice(SensorySection.mouthfeel, 'drying'),
        throwsArgumentError,
      );
      flow.toggleReaction(SensorySection.taste, 'acidity', TasteReaction.liked);
      expect(flow.reactions(SensorySection.taste), {
        'acidity': TasteReaction.liked,
      });
    });
  });
}
