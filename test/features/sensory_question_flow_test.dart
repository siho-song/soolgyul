import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/sensory/revisit_intent.dart';
import 'package:soolgyul/src/core/sensory/sensory_gauges.dart';
import 'package:soolgyul/src/core/sensory/sensory_question_flow.dart';

import '../support/sensory_fixtures.dart';

void main() {
  final definitions = gaugeDefinitions();

  SensoryQuestionFlow create({
    String? category = 'wine',
    String? style = 'red_wine',
    SensoryPart? only,
  }) => SensoryQuestionFlow(
    aromaKeys: {'cherry', 'oak', 'vanilla', 'smoke'},
    gauges: definitions.forDrink(category, style),
    only: only,
  );

  const cherryOnNose = SensoryAnswerItem.aroma(AromaStage.nose, 'cherry');
  const tannin = SensoryAnswerItem.level('tannin');

  test('the pages run revisit, nose, palate (with the finish), review, '
      'complete; only '
      'the revisit answer and the nose wait for an answer', () {
    final flow = create();
    expect(flow.current, SensoryPage.revisit);
    expect(flow.onFirstQuestion, isTrue);
    expect(flow.next, throwsStateError);
    flow.setRevisit(RevisitIntent.wantAgain);
    flow.next();

    expect(flow.current, SensoryPage.nose);
    expect(flow.canContinue, isFalse);
    expect(flow.next, throwsStateError);
    flow.toggleAroma(AromaStage.nose, 'cherry');
    flow.next();

    // The palate page asks the finish under it; it may be left as it is.
    expect(flow.current, SensoryPage.palate);
    expect(flow.asksFinishWithPalate, isTrue);
    expect(flow.canContinue, isTrue);
    flow.next();

    expect(flow.current, SensoryPage.review);
    expect(flow.onLastQuestion, isTrue);
    flow.next();
    expect(flow.current, SensoryPage.complete);
    expect(flow.pages, [
      SensoryPage.revisit,
      SensoryPage.nose,
      SensoryPage.palate,
      SensoryPage.review,
      SensoryPage.complete,
    ]);

    flow.back();
    expect(flow.current, SensoryPage.review);
    expect(flow.aromas(AromaStage.nose), {'cherry'});
  });

  test('SKIP passes the nose with nothing picked, but the palate page is not '
      'left '
      'while nothing at all is sensed', () {
    final flow = create()..setRevisit(RevisitIntent.unsure);
    flow.next();
    flow.toggleAroma(AromaStage.nose, 'cherry');
    flow.toggleBurden(cherryOnNose);
    flow.skipNose();
    expect(flow.noseSkipped, isTrue);
    expect(flow.aromas(AromaStage.nose), isEmpty);
    expect(flow.isBurden(cherryOnNose), isFalse);
    expect(flow.canContinue, isTrue);

    // The palate page, with the finish under it, is the last page that
    // takes a sensation, and the revisit answer alone makes no record.
    flow.next();
    expect(flow.current, SensoryPage.palate);
    expect(flow.hasSensation, isFalse);
    expect(flow.waitsForSensation, isTrue);
    expect(flow.canContinue, isFalse);
    expect(flow.next, throwsStateError);

    // One aroma at any stage is enough, and so is one step on one gauge.
    flow.toggleAroma(AromaStage.palate, 'oak');
    expect(flow.waitsForSensation, isFalse);
    flow.next();
    expect(flow.current, SensoryPage.review);
    final gaugeOnly = create()..setRevisit(RevisitIntent.unsure);
    gaugeOnly
      ..next()
      ..skipNose()
      ..next()
      ..chooseLevel('finish_length', 3);
    expect(gaugeOnly.canContinue, isTrue);

    // A pick after the skip is an answer again.
    flow.back();
    flow.back();
    flow.toggleAroma(AromaStage.nose, 'oak');
    expect(flow.noseSkipped, isFalse);
  });

  test('a gauge holds one step, and a second tap on it keeps the step', () {
    final flow = create();
    expect(flow.level('sweetness'), isNull);
    flow.chooseLevel('sweetness', 2);
    expect(flow.level('sweetness'), 2);
    flow.chooseLevel('sweetness', 4);
    expect(flow.level('sweetness'), 4);
    flow.chooseLevel('sweetness', 4);
    expect(flow.level('sweetness'), 4);

    // A new record starts every gauge it asks in the middle.
    final started = create()..startGaugesInTheMiddle();
    expect(started.level('sweetness'), 3);
    expect(started.level('finish_length'), 3);
    expect(started.hasSensation, isTrue);

    // A red wine is not asked its bubbles, and a step is one of five.
    expect(() => flow.chooseLevel('sparkling', 3), throwsArgumentError);
    expect(() => flow.chooseLevel('sweetness', 0), throwsArgumentError);
    expect(() => flow.chooseLevel('sweetness', 6), throwsArgumentError);
  });

  test('each stage holds its own aromas, in the order picked', () {
    final flow = create();
    flow.toggleAroma(AromaStage.nose, 'oak');
    flow.toggleAroma(AromaStage.nose, 'cherry');
    flow.toggleAroma(AromaStage.palate, 'vanilla');
    flow.toggleAroma(AromaStage.finish, 'oak');
    expect(flow.aromas(AromaStage.nose).toList(), ['oak', 'cherry']);
    expect(flow.aromas(AromaStage.palate), {'vanilla'});
    expect(flow.aromas(AromaStage.finish), {'oak'});

    flow.toggleAroma(AromaStage.nose, 'oak');
    expect(flow.aromas(AromaStage.nose), {'cherry'});
    expect(flow.aromas(AromaStage.finish), {'oak'});
    expect(
      () => flow.toggleAroma(AromaStage.nose, 'invented'),
      throwsArgumentError,
    );
  });

  test('the review lists what was answered under four headings, every item '
      'liked until it is marked', () {
    final flow = create();
    expect(flow.reviewSections, SensoryReviewSection.values);
    for (final section in SensoryReviewSection.values) {
      expect(flow.reviewItems(section), isEmpty);
    }
    flow.toggleAroma(AromaStage.nose, 'oak');
    flow.toggleAroma(AromaStage.nose, 'cherry');
    // Chosen out of the kind's order, listed in it.
    flow.chooseLevel('tannin', 4);
    flow.chooseLevel('sweetness', 2);
    flow.toggleAroma(AromaStage.palate, 'vanilla');
    flow.chooseLevel('finish_character', 3);
    flow.toggleAroma(AromaStage.finish, 'smoke');

    List<String> ids(SensoryReviewSection section) => [
      for (final item in flow.reviewItems(section)) item.id,
    ];
    expect(ids(SensoryReviewSection.nose), [
      'aroma:nose:oak',
      'aroma:nose:cherry',
    ]);
    expect(ids(SensoryReviewSection.palate), [
      'level:sweetness',
      'level:tannin',
    ]);
    expect(ids(SensoryReviewSection.flavor), ['aroma:palate:vanilla']);
    expect(ids(SensoryReviewSection.finish), [
      'level:finish_character',
      'aroma:finish:smoke',
    ]);

    expect(flow.isBurden(tannin), isFalse);
    flow.toggleBurden(tannin);
    flow.toggleBurden(cherryOnNose);
    expect(flow.isBurden(tannin), isTrue);
    expect(flow.isBurden(cherryOnNose), isTrue);
    flow.toggleBurden(tannin);
    expect(flow.isBurden(tannin), isFalse);
    // Only an answer can be marked.
    expect(
      () => flow.toggleBurden(const SensoryAnswerItem.level('acidity')),
      throwsArgumentError,
    );
    expect(
      () => flow.toggleBurden(
        const SensoryAnswerItem.aroma(AromaStage.finish, 'cherry'),
      ),
      throwsArgumentError,
    );
  });

  test('changing a level or removing an aroma clears that item\'s burden '
      'mark and no other', () {
    final flow = create();
    flow.toggleAroma(AromaStage.nose, 'cherry');
    flow.toggleAroma(AromaStage.nose, 'oak');
    flow.chooseLevel('tannin', 5);
    flow.chooseLevel('sweetness', 1);
    const oak = SensoryAnswerItem.aroma(AromaStage.nose, 'oak');
    const sweetness = SensoryAnswerItem.level('sweetness');
    for (final item in [cherryOnNose, oak, tannin, sweetness]) {
      flow.toggleBurden(item);
    }

    flow.chooseLevel('tannin', 3);
    expect(flow.level('tannin'), 3);
    expect(flow.isBurden(tannin), isFalse);
    flow.toggleAroma(AromaStage.nose, 'cherry');
    flow.toggleAroma(AromaStage.nose, 'cherry');
    expect(flow.aromas(AromaStage.nose), {'oak', 'cherry'});
    expect(flow.isBurden(cherryOnNose), isFalse);

    expect(flow.isBurden(oak), isTrue);
    expect(flow.isBurden(sweetness), isTrue);
  });

  test('a part asked again walks its own page, then the review of that part '
      'alone', () {
    final flow = create(only: SensoryPart.palate);
    flow.toggleAroma(AromaStage.nose, 'cherry');
    expect(flow.pages, [SensoryPage.palate, SensoryPage.complete]);
    expect(flow.onFirstQuestion, isTrue);
    expect(flow.onLastQuestion, isTrue);
    // Asked again alone, the palate's page leaves the finish out, and the
    // finish has a page of its own.
    expect(flow.asksFinishWithPalate, isFalse);
    final finish = create(only: SensoryPart.finish);
    expect(finish.pages, [SensoryPage.finish, SensoryPage.complete]);
    expect(finish.asksFinishWithPalate, isFalse);

    flow.chooseLevel('body', 4);
    expect(flow.pages, [
      SensoryPage.palate,
      SensoryPage.review,
      SensoryPage.complete,
    ]);
    expect(flow.reviewSections, [
      SensoryReviewSection.palate,
      SensoryReviewSection.flavor,
    ]);

    // Asked again there is no SKIP: the nose may be left empty, as long as
    // the record holds something sensed elsewhere.
    final nose = create(only: SensoryPart.aroma);
    expect(nose.waitsForSensation, isTrue);
    expect(nose.canContinue, isFalse);
    nose.chooseLevel('body', 3);
    expect(nose.canContinue, isTrue);
    expect(create(only: SensoryPart.finish).reviewSections, [
      SensoryReviewSection.finish,
    ]);
  });

  group('gauges per kind', () {
    List<String> palate(String? category, String? style) => [
      for (final gauge in definitions.forDrink(category, style).palate)
        gauge.axis,
    ];

    test('a wine is asked its tannin only where there is some, and its '
        'bubbles only when it sparkles', () {
      const three = ['sweetness', 'acidity', 'body'];
      expect(palate('wine', 'red_wine'), [...three, 'tannin']);
      expect(palate('wine', 'sparkling_wine'), [...three, 'sparkling']);
      expect(palate('wine', 'white_wine'), three);
      expect(palate('wine', null), three);
    });

    test('탁주 and a traditional bottle of unknown kind are asked their '
        'bubbles; a distilled soju is asked as a spirit, in its own words', () {
      const three = ['sweetness', 'acidity', 'body'];
      expect(palate('korean_traditional', 'takju'), [...three, 'sparkling']);
      expect(palate('korean_traditional', null), [...three, 'sparkling']);
      expect(palate('korean_traditional', 'korean_fruit_wine'), three);
      final soju = definitions.forDrink('korean_traditional', 'distilled_soju');
      expect(
        [for (final gauge in soju.palate) gauge.label],
        ['단맛', '바디', '자극'],
      );
      expect(palate('korean_traditional', 'distilled_soju'), [
        'sweetness',
        'body',
        'spice',
      ]);
      expect(soju.of('sweetness')!.label, '단맛');
    });

    test('whisky is asked spice and peat, sake its acidity and its umami '
        'apart', () {
      expect(palate('whisky', 'single_malt_whisky'), [
        'sweetness',
        'body',
        'spice',
        'peat',
      ]);
      expect(palate('sake', 'junmai'), [
        'sweetness',
        'acidity',
        'umami',
        'body',
      ]);
    });

    test('a kind without gauges of its own, or none, is asked the three of '
        'a wine in a wine\'s words', () {
      final wine = definitions.forDrink('wine', 'white_wine');
      for (final category in ['beer', null]) {
        final asked = definitions.forDrink(category, 'red_wine');
        expect(
          [for (final gauge in asked.palate) gauge.axis],
          ['sweetness', 'acidity', 'body'],
          reason: '$category',
        );
        expect(asked.palate.first.label, wine.palate.first.label);
      }
    });

    test('every kind is asked the finish\'s length and character, worded for '
        'the kind', () {
      for (final category in ['wine', 'whisky', 'korean_traditional', 'sake']) {
        final asked = definitions.forDrink(category, null);
        expect(
          [for (final gauge in asked.finish) gauge.axis],
          ['finish_length', 'finish_character'],
          reason: category,
        );
        // The character runs between two ends and its steps have no hint.
        expect(asked.of('finish_character')!.ends, isNotNull);
        expect(asked.of('finish_character')!.levelAt(3).label, '밸런스');
      }
      final wine = definitions.forDrink('wine', 'red_wine');
      expect(wine.of('sweetness')!.levelAt(2).label, '드라이 · 산뜻한 기본 드라이');
      expect(wine.of('sweetness')!.chipLabel(2), '당도 · 드라이');
      expect(wine.of('peat'), isNull);
      expect(definitions.forDrink('whisky', null).of('sweetness')!.label, '단맛');
    });

    test('gauge definitions of another version, or a gauge without five '
        'steps, are refused', () {
      final source = readJsonAsset('catalog/sensory/gauge-definitions.json');
      expect(
        () => SensoryGaugeDefinitions.fromJson({...source, 'version': 1}),
        throwsFormatException,
      );
      expect(
        () => SensoryGauge(
          axis: 'sweetness',
          label: '당도',
          levels: const [GaugeLevel(term: '드라이')],
        ),
        throwsFormatException,
      );
    });
  });
}
