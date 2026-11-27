import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/core/sensory/revisit_intent.dart';
import 'package:soolgyul/src/core/sensory/sensory_gauges.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/core/sensory/sensory_question_flow.dart';
import 'package:soolgyul/src/features/onboarding/presentation/sensory/aroma_picker.dart';
import 'package:soolgyul/src/features/onboarding/presentation/sensory/sensory_question_copy.dart';
import 'package:soolgyul/src/features/onboarding/presentation/sensory_questionnaire_screen.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/aroma_picture.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';

import '../support/sensory_fixtures.dart';

void main() {
  final registry = sensoryRegistry();
  final menu = OnboardingAromaMenu.forDrink('wine', 'red_wine');
  final redWine = gaugesFor('wine', 'red_wine');

  /// A flow standing on [page], every page before it passed unanswered.
  SensoryQuestionFlow flowAt(SensoryPage page, [GaugeSet? gauges]) {
    final flow = registry.createFlow(gauges ?? redWine)
      ..setRevisit(RevisitIntent.wantAgain);
    while (flow.current != page) {
      if (flow.current == SensoryPage.nose) flow.skipNose();
      flow.next();
    }
    return flow;
  }

  Future<void> pump(
    WidgetTester tester,
    SensoryQuestionFlow flow, {
    VoidCallback? complete,
    OnboardingAromaMenu? aromaMenu,
  }) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The SKIP lives in the app header; this stands in for it.
    final skip = SensorySkipNotifier();
    addTearDown(skip.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          appBar: AppBar(actions: [SensorySkipHeaderAction(skip: skip)]),
          body: SensoryQuestionnaireScreen(
            // A flow pumped after another starts with a fresh screen.
            key: ObjectKey(flow),
            skip: skip,
            flow: flow,
            registry: registry,
            aromaMenu: aromaMenu ?? menu,
            onChanged: () {},
            onComplete: complete ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
    // No page sorts an answer into liked or disliked while it is given.
    expect(find.textContaining('좋았어요'), findsNothing);
    expect(find.textContaining('아쉬웠어요'), findsNothing);
    expect(find.text('맞는 표현이 없어요'), findsNothing);
    // No page has a text field; answers stay choices.
    expect(find.byType(TextFormField), findsNothing);
  }

  AppButton nextButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.byKey(const ValueKey('sensory-next')));

  testWidgets('the revisit question offers three answers and no unsure one; '
      'SKIP stores it', (tester) async {
    final flow = registry.createFlow(redWine);
    await pump(tester, flow);
    expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);
    expect(find.text('솔직한 내 느낌을 가볍게 골라 주세요.'), findsOneWidget);
    for (final (key, label) in [
      ('revisit:wantAgain', '꼭 다시 마시고 싶어요'),
      ('revisit:wouldAcceptAgain', '무난하게 괜찮았어요'),
      ('revisit:doNotWantAgain', '아니요, 다른 술을 마셔볼래요'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('아직은 잘 모르겠어요'), findsNothing);
    expect(nextButton(tester).onPressed, isNull);
    expect(find.byKey(const ValueKey('revisit:unsure')), findsOneWidget);
    await tap(tester, 'revisit:unsure');
    expect(flow.revisit, RevisitIntent.unsure);
    expect(flow.current, SensoryPage.nose);
  });

  testWidgets('the nose shows SKIP in the header, not the body; the pages '
      'that may be left empty have none', (tester) async {
    final flow = flowAt(SensoryPage.nose);
    await pump(tester, flow);

    expect(find.text('잘 모르겠어요'), findsNothing);
    expect(find.text('SKIP'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const ValueKey('nose:unsure')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    expect(flow.noseSkipped, isTrue);
    expect(flow.current, SensoryPage.palate);
    expect(find.text('SKIP'), findsNothing);
    // The finish stands under the palate's gauges, on the same page.
    expect(find.text('여운(Finish)'), findsOneWidget);
    expect(find.text('SKIP'), findsNothing);
  });

  Finder chip(String key, [String stage = 'nose']) =>
      find.byKey(ValueKey('aroma:$stage:$key'));
  String word(String key) => registry.aromaLabel(key)!;

  testWidgets('the aroma question: the menu in tabs under the question, no '
      'search, no check mark, any number of aromas', (tester) async {
    final flow = flowAt(SensoryPage.nose);
    await pump(tester, flow);

    // Every heading is a tab; the first tab shows its chips (twenty or
    // fewer, so all of them) and the other tabs' chips wait under them.
    for (final group in menu.groups) {
      expect(find.text(group.title), findsOneWidget);
    }
    for (final each in menu.groups.first.chips) {
      expect(chip(each.key), findsOneWidget);
    }
    for (final each in menu.groups[1].chips) {
      expect(chip(each.key), findsNothing);
    }
    // No search and no count: any number of aromas is taken.
    expect(find.text('향(Aroma)'), findsOneWidget);
    const description = '느낀 인상들을 골라 주세요.';
    expect(find.text(description), findsOneWidget);
    expect(find.textContaining('/5'), findsNothing);
    expect(find.byKey(const ValueKey('aroma-search:open')), findsNothing);
    expect(
      tester.getTopLeft(find.text(menu.groups.first.title)).dy,
      greaterThan(tester.getBottomLeft(find.text(description)).dy),
    );
    // Nothing is picked yet, so there is no bar.
    expect(find.byKey(const ValueKey('aroma-picked')), findsNothing);

    // 다음 waits for a pick; SKIP in the header is the way past the page.
    expect(nextButton(tester).onPressed, isNull);

    // Every chip shown may be picked: nothing is refused.
    final keys = [for (final each in menu.groups.first.chips.take(6)) each.key];
    for (final key in keys) {
      await tester.ensureVisible(chip(key));
      await tester.tap(chip(key));
      await tester.pumpAndSettle();
    }
    expect(keys.length, greaterThan(5));
    expect(flow.aromas(AromaStage.nose), keys.toSet());
    expect(find.byType(SnackBar), findsNothing);
    // Colour alone marks a picked chip; no check mark appears.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppChip && widget.leadingIcon != null,
      ),
      findsNothing,
    );
    // Three to a row from the left, each as wide as its name.
    final row = menu.groups.first.chips.take(4).toList();
    expect(
      tester.getTopLeft(chip(row.first.key)).dx,
      tester.getTopLeft(find.byType(AromaPicker)).dx,
    );
    for (final each in row.skip(1).take(2)) {
      expect(
        tester.getTopLeft(chip(each.key)).dy,
        tester.getTopLeft(chip(row.first.key)).dy,
      );
    }
    expect(
      tester.getTopLeft(chip(row[3].key)).dy,
      greaterThan(tester.getTopLeft(chip(row.first.key)).dy),
    );
    expect(
      tester.getTopRight(chip(row[2].key)).dx,
      lessThan(tester.getTopRight(find.byType(AromaPicker)).dx),
    );

    await tap(tester, 'sensory-next');
    expect(flow.current, SensoryPage.palate);
  });

  testWidgets('a tab shows its heading\'s chips alone; a picked chip carries '
      'the number of its turn, and keeps it when its tab is left', (
    tester,
  ) async {
    final flow = flowAt(SensoryPage.nose);
    await pump(tester, flow);
    final [first, second] = menu.groups.take(2).toList();
    Finder turn(String key) => find.byKey(ValueKey('aroma:nose:$key:turn'));

    await tap(tester, 'aroma:nose:${first.chips[2].key}');
    await tap(tester, 'aroma-tab:1');
    for (final each in second.chips.take(6)) {
      expect(chip(each.key), findsOneWidget);
    }
    expect(chip(first.chips[2].key), findsNothing);
    await tap(tester, 'aroma:nose:${second.chips[0].key}');
    expect(
      find.descendant(of: turn(second.chips[0].key), matching: find.text('2')),
      findsOneWidget,
    );

    await tap(tester, 'aroma-tab:0');
    expect(
      find.descendant(of: turn(first.chips[2].key), matching: find.text('1')),
      findsOneWidget,
    );
    expect(turn(first.chips[0].key), findsNothing);
    // Unpicking the first moves the next one up to 1.
    await tap(tester, 'aroma:nose:${first.chips[2].key}');
    expect(turn(first.chips[2].key), findsNothing);
    await tap(tester, 'aroma-tab:1');
    expect(
      find.descendant(of: turn(second.chips[0].key), matching: find.text('1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap picks an aroma and a second unpicks it; the turn on '
      'its chip shows the pick', (tester) async {
    final flow = flowAt(SensoryPage.nose);
    final [first, second] = menu.keys.take(2).toList();
    await pump(tester, flow);
    Finder turn(String key) => find.byKey(ValueKey('aroma:nose:$key:turn'));

    await tap(tester, 'aroma:nose:$first');
    await tap(tester, 'aroma:nose:$second');
    expect(flow.aromas(AromaStage.nose).toList(), [first, second]);
    for (final key in [first, second]) {
      expect(tester.widget<AppChip>(chip(key)).selected, isTrue);
      expect(tester.widget<AppChip>(chip(key)).tone, AppChipTone.positive);
    }
    // The picks are shown by the turn on their chips alone; no bar.
    expect(find.byKey(const ValueKey('aroma-picked')), findsNothing);
    expect(
      find.descendant(of: turn(second), matching: find.text('2')),
      findsOneWidget,
    );

    // A second tap unpicks.
    await tap(tester, 'aroma:nose:$first');
    expect(flow.aromas(AromaStage.nose), {second});
    expect(tester.widget<AppChip>(chip(first)).selected, isFalse);
    expect(turn(first), findsNothing);
    await tap(tester, 'aroma:nose:$second');
    expect(flow.aromas(AromaStage.nose), isEmpty);
    expect(nextButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a double tap on 다음 or SKIP moves one question, not two', (
    tester,
  ) async {
    Future<void> doubleTap(Finder target) async {
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(target, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    // 다음 on the palate: the second tap would save the review unread.
    var saved = 0;
    final byNext = flowAt(SensoryPage.palate)..chooseLevel('body', 3);
    await pump(tester, byNext, complete: () => saved++);
    await doubleTap(find.byKey(const ValueKey('sensory-next')));
    expect(byNext.current, SensoryPage.review);
    expect(saved, 0);
    // Once the question has settled, 다음 answers again.
    await tap(tester, 'sensory-next');
    expect(saved, 1);

    // SKIP on 재음용 의사: the second tap would skip the nose unread.
    final bySkip = registry.createFlow(redWine);
    await pump(tester, bySkip);
    await doubleTap(find.text('SKIP'));
    expect(bySkip.current, SensoryPage.nose);
    expect(bySkip.noseSkipped, isFalse);
  });

  /// The middle of a step of a gauge's bar.
  Offset stop(WidgetTester tester, String axis, int step) =>
      tester.getCenter(find.byKey(ValueKey('gauge:$axis:$step')));

  /// The slider a screen reader is given for a gauge, by the gauge's name.
  Semantics sliderOf(WidgetTester tester, String label) =>
      tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.slider == true &&
              widget.properties.label == label,
        ),
      );

  testWidgets('a gauge row: the name at the left, a bar of five steps, the '
      'ends and 보통 under it; a tap fills the step and a second keeps it', (
    tester,
  ) async {
    final flow = flowAt(SensoryPage.palate);
    await pump(tester, flow);
    expect(find.text('맛과 질감(Palate)'), findsOneWidget);
    expect(find.text('입안에서 느껴진 인상을 가볍게 선택해 주세요.'), findsOneWidget);

    // A red wine: its tannin, not its bubbles. Each bar has five steps, a
    // tap target high, with no number on them and nothing chosen.
    for (final (axis, label) in [
      ('sweetness', '당도'),
      ('acidity', '산미'),
      ('body', '바디'),
      ('tannin', '탄닌'),
    ]) {
      final name = find.byKey(ValueKey('gauge-name:$axis'));
      expect(tester.widget<Text>(name).data, label);
      for (var step = 1; step <= 5; step++) {
        final column = find.byKey(ValueKey('gauge:$axis:$step'));
        expect(column, findsOneWidget);
        expect(
          tester.getSize(column).height,
          greaterThanOrEqualTo(AppSizes.minimumTapTarget),
        );
        expect(find.text('$step'), findsNothing);
      }
      // The name stands left of the bar, on its line.
      expect(
        tester.getTopRight(name).dx,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(ValueKey('gauge:$axis:1'))).dx,
        ),
      );
      expect(flow.level(axis), isNull);
    }
    expect(find.byKey(const ValueKey('gauge-knob:sweetness')), findsNothing);
    expect(find.byKey(const ValueKey('gauge-label:sweetness')), findsNothing);
    // The steps stand evenly apart; under the bar's ends are the words of
    // the two characters it runs between, and 보통 under its middle.
    expect(
      stop(tester, 'body', 4).dx - stop(tester, 'body', 3).dx,
      closeTo(stop(tester, 'body', 3).dx - stop(tester, 'body', 2).dx, .01),
    );
    final body = redWine.palate.firstWhere((gauge) => gauge.axis == 'body');
    expect(body.ends, ('라이트', '풀바디'));
    final low = find.text(body.ends!.$1);
    final high = find.text(body.ends!.$2);
    expect(low, findsOneWidget);
    expect(high, findsOneWidget);
    expect(
      find.text('보통'),
      findsNWidgets(redWine.palate.length + redWine.finish.length),
    );
    expect(tester.getCenter(low).dx, lessThan(stop(tester, 'body', 2).dx));
    expect(tester.getCenter(high).dx, greaterThan(stop(tester, 'body', 4).dx));
    expect(
      tester.getTopLeft(low).dy,
      greaterThanOrEqualTo(stop(tester, 'body', 1).dy),
    );
    expect(find.byKey(const ValueKey('gauge:sparkling:1')), findsNothing);
    expect(find.byKey(const ValueKey('gauge:bitterness:1')), findsNothing);

    // A tap chooses its step; no word of the step is written beside it.
    await tap(tester, 'gauge:sweetness:2');
    expect(flow.level('sweetness'), 2);
    expect(find.textContaining('산뜻한 기본 드라이'), findsNothing);
    expect(flow.level('acidity'), isNull);
    await tap(tester, 'gauge:sweetness:4');
    expect(flow.level('sweetness'), 4);
    await tap(tester, 'gauge:sweetness:4');
    expect(flow.level('sweetness'), 4);

    // To a screen reader the bar is a slider named by its axis: a step up
    // from nothing is the first step, and none goes below it.
    final sweetness = redWine.palate.firstWhere(
      (gauge) => gauge.axis == 'sweetness',
    );
    Semantics slider() => sliderOf(tester, sweetness.label);
    final fresh = flowAt(SensoryPage.palate);
    await pump(tester, fresh);
    expect(slider().properties.value, '선택 안 함');
    expect(slider().properties.onDecrease, isNull);
    slider().properties.onIncrease!();
    await tester.pumpAndSettle();
    expect(fresh.level('sweetness'), 1);
    expect(slider().properties.value, sweetness.levelAt(1).term);
    expect(slider().properties.onDecrease, isNull);
    slider().properties.onIncrease!();
    await tester.pumpAndSettle();
    expect(fresh.level('sweetness'), 2);
    expect(slider().properties.value, sweetness.levelAt(2).term);
    slider().properties.onDecrease!();
    await tester.pumpAndSettle();
    expect(fresh.level('sweetness'), 1);
    // Left empty, the page still moves on.
    expect(nextButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a drag along a gauge moves the choice from step to step; it '
      'never clears the gauge, and a drag up or down chooses nothing', (
    tester,
  ) async {
    final flow = flowAt(SensoryPage.palate);
    await pump(tester, flow);
    Future<void> expectAt(int step) async {
      await tester.pumpAndSettle();
      expect(flow.level('acidity'), step);
    }

    // From nothing chosen, the drag chooses the step it starts on.
    final second = stop(tester, 'acidity', 2);
    final drag = await tester.startGesture(second);
    await drag.moveBy(const Offset(24, 0));
    await expectAt(2);
    await drag.moveTo(stop(tester, 'acidity', 4));
    await expectAt(4);
    // Moving within the step it holds does not clear it.
    await drag.moveTo(stop(tester, 'acidity', 4) + const Offset(3, 0));
    await drag.moveTo(stop(tester, 'acidity', 4) - const Offset(3, 0));
    await expectAt(4);
    // Past the end of the bar is its last step.
    await drag.moveBy(const Offset(600, 0));
    await expectAt(5);
    await drag.up();
    await expectAt(5);

    // Up and down belongs to a page that scrolls: nothing is chosen.
    tester.view.physicalSize = const Size(411, 500);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('gauge:body:3')));
    await tester.pumpAndSettle();
    final scroll = await tester.startGesture(stop(tester, 'body', 3));
    await scroll.moveBy(const Offset(0, -60));
    await scroll.up();
    await tester.pumpAndSettle();
    expect(flow.level('body'), isNull);
    expect(tester.takeException(), isNull);
  });

  for (final (name, category, style, axes) in [
    (
      'a sparkling wine',
      'wine',
      'sparkling_wine',
      ['sweetness', 'acidity', 'body', 'sparkling'],
    ),
    ('a whisky', 'whisky', null, ['sweetness', 'body', 'spice', 'peat']),
    ('a sake', 'sake', 'junmai', ['sweetness', 'acidity', 'umami', 'body']),
    (
      'a distilled soju',
      'korean_traditional',
      'distilled_soju',
      ['sweetness', 'body', 'spice'],
    ),
  ]) {
    testWidgets('$name is shown the gauges of its kind, in its words', (
      tester,
    ) async {
      final gauges = gaugesFor(category, style);
      await pump(tester, flowAt(SensoryPage.palate, gauges));
      final shown = tester
          .widgetList(
            find.byWidgetPredicate((widget) {
              final key = widget.key;
              return key is ValueKey<String> &&
                  key.value.startsWith('gauge-name:');
            }),
          )
          .map(
            (widget) => (widget.key! as ValueKey<String>).value.substring(11),
          );
      expect(shown, [...axes, for (final gauge in gauges.finish) gauge.axis]);
      for (final gauge in gauges.palate) {
        expect(find.text(gauge.label), findsOneWidget);
      }
    });
  }

  AppChip reviewChip(WidgetTester tester, String id) =>
      tester.widget<AppChip>(find.byKey(ValueKey('review:$id')));

  testWidgets('the review lists the four groups that hold answers, a tap '
      'turns a chip to the burden look and a second back, and its button '
      'says 저장', (tester) async {
    final [first, second] = menu.keys.take(2).toList();
    final flow = registry.createFlow(redWine)
      ..setRevisit(RevisitIntent.wantAgain)
      ..next()
      ..toggleAroma(AromaStage.nose, first)
      ..next()
      ..chooseLevel('sweetness', 2)
      ..chooseLevel('tannin', 4)
      ..toggleAroma(AromaStage.palate, second)
      ..chooseLevel('finish_length', 4)
      ..chooseLevel('finish_character', 3)
      ..toggleAroma(AromaStage.finish, 'oak')
      ..next();
    var completed = 0;
    await pump(tester, flow, complete: () => completed++);

    expect(find.text('아쉬웠던 부분이 있으면 골라주세요.'), findsOneWidget);
    // No description under it: the sections follow the title.
    expect(find.textContaining('없다면 바로 저장'), findsNothing);
    expect(find.text('SKIP'), findsNothing);
    expect(nextButton(tester).label, '저장');

    // The four groups, top to bottom, each with its answers as chips.
    final groups = {
      'nose': ('향', ['aroma:nose:$first']),
      'palate': ('맛 · 질감', ['level:sweetness', 'level:tannin']),
      'flavor': ('입안에서 퍼진 풍미', ['aroma:palate:$second']),
      'finish': (
        '여운',
        ['level:finish_length', 'level:finish_character', 'aroma:finish:oak'],
      ),
    };
    var above = double.negativeInfinity;
    for (final MapEntry(key: name, value: (title, ids)) in groups.entries) {
      final section = find.byKey(ValueKey('review-section:$name'));
      // The finish's heading shares its word with its length gauge.
      expect(
        find.descendant(of: section, matching: find.text(title)).first,
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<AppChip>(
              find.descendant(of: section, matching: find.byType(AppChip)),
            )
            .map((chip) => (chip.key! as ValueKey<String>).value),
        [for (final id in ids) 'review:$id'],
      );
      final top = tester.getTopLeft(section).dy;
      expect(top, greaterThan(above));
      above = top;
    }
    // An aroma by its name; a gauge by the step's term, under the gauge's
    // name. An aroma keeps the picture of its menu chip; a gauge has none.
    AromaPicture picture(String id) =>
        reviewChip(tester, id).leading! as AromaPicture;
    expect(reviewChip(tester, 'aroma:nose:$first').label, word(first));
    expect(
      picture('aroma:nose:$first').chip,
      same(OnboardingAromaMenu.chipOf(first)),
    );
    for (final (axis, name, term) in [
      ('sweetness', '당도', '드라이'),
      ('tannin', '탄닌', '단단함'),
      ('finish_length', '여운', '미디엄 롱'),
      ('finish_character', '끝맛', '밸런스'),
    ]) {
      final chip = find.byKey(ValueKey('review:level:$axis'));
      expect(reviewChip(tester, 'level:$axis').label, term);
      expect(reviewChip(tester, 'level:$axis').leading, isNull);
      expect(
        tester.getTopLeft(find.text(name).last).dy,
        lessThan(tester.getTopLeft(chip).dy),
      );
    }
    expect(reviewChip(tester, 'aroma:finish:oak').label, word('oak'));
    expect(
      picture('aroma:finish:oak').chip.picture,
      'assets/icons/aromas/oak.webp',
    );

    // Every chip starts plain, in the text's own dark.
    for (final chip in tester.widgetList<AppChip>(find.byType(AppChip))) {
      expect(chip.selected, isFalse);
      expect(chip.tone, AppChipTone.neutral);
    }
    const tannin = SensoryAnswerItem.level('tannin');
    const oak = SensoryAnswerItem.aroma(AromaStage.finish, 'oak');
    await tap(tester, 'review:level:tannin');
    await tap(tester, 'review:aroma:finish:oak');
    expect(flow.isBurden(tannin), isTrue);
    expect(flow.isBurden(oak), isTrue);
    // A marked chip alone takes the warning colour, and says so.
    for (final id in ['level:tannin', 'aroma:finish:oak']) {
      expect(reviewChip(tester, id).selected, isTrue);
      expect(reviewChip(tester, id).tone, AppChipTone.negative);
    }
    expect(reviewChip(tester, 'level:sweetness').selected, isFalse);
    expect(reviewChip(tester, 'level:sweetness').tone, AppChipTone.neutral);
    expect(find.bySemanticsLabel('탄닌 · 단단함, 아쉬웠던 부분으로 표시됨'), findsOneWidget);
    expect(find.bySemanticsLabel('당도 · 드라이'), findsOneWidget);
    await tap(tester, 'review:aroma:finish:oak');
    expect(flow.isBurden(oak), isFalse);
    expect(reviewChip(tester, 'aroma:finish:oak').selected, isFalse);
    expect(reviewChip(tester, 'aroma:finish:oak').tone, AppChipTone.neutral);

    expect(completed, 0);
    await tap(tester, 'sensory-next');
    expect(completed, 1);
    expect(registry.readAnswers(flow)['sensory_palate_level'], [
      'level:sweetness:2:liked',
      'level:tannin:4:disliked',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aroma chips of the review that take a second row stand a gap '
      'under the first, as wide as the gap beside them', (tester) async {
    final picked = menu.keys.take(5).toList();
    final flow = registry.createFlow(redWine)
      ..setRevisit(RevisitIntent.wantAgain)
      ..next();
    for (final key in picked) {
      flow.toggleAroma(AromaStage.nose, key);
    }
    flow
      ..next()
      ..next();
    await pump(tester, flow);

    final rects = [
      for (final key in picked)
        tester.getRect(find.byKey(ValueKey('review:aroma:nose:$key'))),
    ];
    final firstRow = rects.where((rect) => rect.top == rects.first.top);
    final secondRow = rects.where((rect) => rect.top > rects.first.top);
    expect(secondRow, isNotEmpty, reason: 'five chips do not fit one row');
    expect(
      secondRow.first.top - firstRow.first.bottom,
      firstRow.elementAt(1).left - firstRow.first.right,
    );
  });

  testWidgets('a group with nothing answered is left out of the review, '
      'heading and all', (tester) async {
    final flow = flowAt(SensoryPage.palate)..chooseLevel('body', 5);
    flow.next();
    expect(flow.current, SensoryPage.review);
    await pump(tester, flow);
    expect(find.byKey(const ValueKey('review-section:palate')), findsOneWidget);
    expect(find.text('맛 · 질감'), findsOneWidget);
    for (final (name, title) in [
      ('nose', '향'),
      ('flavor', '입안에서 퍼진 풍미'),
      ('finish', '여운'),
    ]) {
      expect(find.byKey(ValueKey('review-section:$name')), findsNothing);
      expect(find.text(title), findsNothing);
    }
    expect(find.byType(AppChip), findsOneWidget);
    expect(reviewChip(tester, 'level:body').label, '풀바디');
  });

  testWidgets('a part asked again ends on the review of that part, with 이전 '
      'under it; left with nothing to review it ends on 완료', (tester) async {
    final flow = registry.createFlow(redWine, only: SensoryPart.palate)
      ..toggleAroma(AromaStage.nose, menu.keys.first);
    var completed = 0;
    await pump(tester, flow, complete: () => completed++);
    expect(find.text('SKIP'), findsNothing);
    expect(nextButton(tester).label, '완료');
    expect(find.byKey(const ValueKey('sensory-back')), findsNothing);
    // The palate asks its gauges alone; no aromas.
    expect(find.byType(AromaPicker), findsNothing);
    expect(flow.aromas(AromaStage.palate), isEmpty);

    await tap(tester, 'gauge:acidity:1');
    expect(nextButton(tester).label, '다음');
    await tap(tester, 'sensory-next');
    expect(completed, 0);
    expect(nextButton(tester).label, '저장');
    // The nose's aroma belongs to another part.
    expect(find.byKey(const ValueKey('review-section:nose')), findsNothing);
    expect(reviewChip(tester, 'level:acidity').label, '로우');
    expect(find.text('이전'), findsOneWidget);
    await tap(tester, 'sensory-back');
    expect(flow.current, SensoryPage.palate);
    await tap(tester, 'sensory-next');
    await tap(tester, 'sensory-next');
    expect(completed, 1);

    // The nose asked again and left empty is kept as skipped.
    final nose = registry.createFlow(redWine, only: SensoryPart.aroma)
      ..chooseLevel('body', 3);
    await pump(tester, nose, complete: () => completed++);
    expect(nextButton(tester).label, '완료');
    expect(find.text(SensoryQuestionCopy.sensationRequired), findsNothing);
    await tap(tester, 'sensory-next');
    expect(nose.noseSkipped, isTrue);
    expect(completed, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last page that takes sensations is not left while the '
      'record holds none, and says so over its button', (tester) async {
    final note = find.text(SensoryQuestionCopy.sensationRequired);
    // The whole flow: the nose skipped and the palate page, with the
    // finish under it, left empty.
    final flow = flowAt(SensoryPage.palate);
    await pump(tester, flow);
    expect(note, findsOneWidget);
    expect(nextButton(tester).onPressed, isNull);
    await tap(tester, 'gauge:finish_length:3');
    expect(note, findsNothing);
    expect(nextButton(tester).onPressed, isNotNull);
    // A second tap on the chosen stop keeps it, and the page stays open.
    await tap(tester, 'gauge:finish_length:3');
    expect(flow.level('finish_length'), 3);
    expect(note, findsNothing);
    expect(nextButton(tester).onPressed, isNotNull);

    // A part asked again: it is not finished while it holds no answer.
    var completed = 0;
    final part = registry.createFlow(redWine, only: SensoryPart.palate);
    await pump(tester, part, complete: () => completed++);
    expect(part.level('body'), isNull);
    expect(note, findsOneWidget);
    expect(nextButton(tester).label, '완료');
    expect(nextButton(tester).onPressed, isNull);
    await tap(tester, 'gauge:body:3');
    expect(note, findsNothing);
    expect(nextButton(tester).onPressed, isNotNull);
    expect(completed, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tab shows twenty chips and 더보기; 더보기 shows them all and '
      'turns into 접기, each tab apart', (tester) async {
    final white = OnboardingAromaMenu.forDrink('wine', 'white_wine');
    final flow = registry.createFlow(gaugesFor('wine', 'white_wine'))
      ..setRevisit(RevisitIntent.wantAgain)
      ..next();
    await pump(tester, flow, aromaMenu: white);
    final [first, second] = white.groups.take(2).toList();
    expect(first.chips.length, greaterThan(20));
    expect(second.chips.length, lessThanOrEqualTo(20));
    Finder more(int tab) => find.byKey(ValueKey('aroma-more:$tab'));

    expect(more(0), findsOneWidget);
    expect(find.text('더보기'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(chip(first.chips[19].key), findsOneWidget);
    expect(chip(first.chips[20].key), findsNothing);
    // Centred under the chips, as a button that says it is closed.
    await tester.ensureVisible(more(0));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('더보기')).dx,
      lessThan(tester.getCenter(find.byType(AromaPicker)).dx),
    );
    expect(
      tester.getTopLeft(more(0)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(chip(first.chips[19].key)).dy),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('더보기')),
      isSemantics(
        label: '더보기',
        isButton: true,
        isExpanded: false,
        hasTapAction: true,
      ),
    );

    await tap(tester, 'aroma-more:0');
    for (final each in first.chips) {
      expect(chip(each.key), findsOneWidget);
    }
    expect(find.text('접기'), findsOneWidget);
    expect(find.text('더보기'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('접기')),
      isSemantics(label: '접기', isButton: true, isExpanded: true),
    );
    await tap(tester, 'aroma:nose:${first.chips.last.key}');

    // A tab of twenty or fewer has no 더보기; the opened tab stays open.
    await tap(tester, 'aroma-tab:1');
    expect(more(1), findsNothing);
    for (final each in second.chips) {
      expect(chip(each.key), findsOneWidget);
    }
    await tap(tester, 'aroma-tab:0');
    expect(find.text('접기'), findsOneWidget);

    // 접기 hides the rest again; a pick it hides stays picked.
    await tap(tester, 'aroma-more:0');
    expect(chip(first.chips.last.key), findsNothing);
    expect(find.text('더보기'), findsOneWidget);
    expect(flow.aromas(AromaStage.nose), {first.chips.last.key});
    expect(tester.takeException(), isNull);
  });

  testWidgets('the palate page asks the finish under its gauges; a part '
      'asked again shows its own gauges alone', (tester) async {
    final flow = flowAt(SensoryPage.palate);
    await pump(tester, flow);
    const finishDescription = '목 넘김 뒤에 남은 느낌을 가볍게 선택해 주세요.';
    final heading = find.text('여운(Finish)');
    expect(find.text('맛과 질감(Palate)'), findsOneWidget);
    expect(heading, findsOneWidget);
    expect(find.text(finishDescription), findsOneWidget);
    // The palate's gauges, the finish's heading and description, then its
    // gauges, top to bottom.
    final lastPalate = redWine.palate.last.axis;
    final firstFinish = redWine.finish.first.axis;
    expect(
      tester.getTopLeft(heading).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(ValueKey('gauge:$lastPalate:1'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.text(finishDescription)).dy,
      greaterThan(tester.getBottomLeft(heading).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(ValueKey('gauge-name:$firstFinish'))).dy,
      greaterThan(tester.getBottomLeft(find.text(finishDescription)).dy),
    );
    expect(
      tester.getSemantics(heading),
      isSemantics(label: '여운(Finish)', isHeader: true),
    );
    // Both parts are answered on the one page.
    await tap(tester, 'gauge:$lastPalate:2');
    await tap(tester, 'gauge:$firstFinish:4');
    expect(flow.level(lastPalate), 2);
    expect(flow.level(firstFinish), 4);

    // Asked again alone, the palate has no finish, and the finish has a
    // page of its own.
    await pump(tester, registry.createFlow(redWine, only: SensoryPart.palate));
    expect(heading, findsNothing);
    expect(find.byKey(ValueKey('gauge:$firstFinish:1')), findsNothing);
    await pump(tester, registry.createFlow(redWine, only: SensoryPart.finish));
    expect(find.text('맛과 질감(Palate)'), findsNothing);
    expect(heading, findsOneWidget);
    expect(find.byKey(ValueKey('gauge:$firstFinish:1')), findsOneWidget);
    expect(find.byKey(ValueKey('gauge:$lastPalate:1')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
