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
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';

import '../support/sensory_fixtures.dart';

void main() {
  final registry = sensoryRegistry();
  final engine = aromaEngine();
  final menu = OnboardingAromaMenu.forDrink('wine', 'red_wine');
  final redWine = gaugesFor('wine', 'red_wine');
  // An aroma the menu has no chip for, reachable only through the search.
  final extra = registry.aromaKeys.firstWhere(
    (key) => !menu.keys.contains(key),
  );

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
            aromaEngine: engine,
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
    // The aroma search box is the only text field; answers stay choices.
    expect(
      find.byType(TextFormField).evaluate().length,
      find
          .descendant(
            of: find.byKey(const ValueKey('sensory-aroma-search')),
            matching: find.byType(TextFormField),
          )
          .evaluate()
          .length,
    );
  }

  AppButton nextButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.byKey(const ValueKey('sensory-next')));

  testWidgets('the revisit question offers three answers and no unsure one; '
      'SKIP stores it', (tester) async {
    final flow = registry.createFlow(redWine);
    await pump(tester, flow);
    expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);
    expect(find.text('솔직한 내 느낌을 가볍게 골라 보세요.'), findsOneWidget);
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
    expect(nextButton(tester).onPressed, isNotNull);
    await tap(tester, 'sensory-next');
    expect(flow.current, SensoryPage.finish);
    expect(find.text('SKIP'), findsNothing);
  });

  Finder chip(String key, [String stage = 'nose']) =>
      find.byKey(ValueKey('aroma:$stage:$key'));
  Finder picked(String key, [String stage = 'nose']) =>
      find.byKey(ValueKey('picked:aroma:$stage:$key'));
  String word(String key) => registry.aromaLabel(key)!;

  /// The words of the bar's chips, left to right.
  List<String> bar(WidgetTester tester) => [
    for (final chip in tester.widgetList<AppChip>(
      find.descendant(
        of: find.byKey(const ValueKey('aroma-picked')),
        matching: find.byType(AppChip),
      ),
    ))
      chip.label,
  ];

  /// A touch on a bar chip's × unpicks its aroma.
  Future<void> remove(WidgetTester tester, String key) async {
    final cross = find.descendant(
      of: picked(key),
      matching: find.bySemanticsLabel('${word(key)} 빼기'),
    );
    await tester.ensureVisible(cross);
    await tester.pumpAndSettle();
    await tester.tap(cross);
    await tester.pumpAndSettle();
  }

  /// A touch on a bar chip's name, clear of its ×.
  Future<void> tapBarChipBody(WidgetTester tester, String key) async {
    await tester.tapAt(
      tester.getRect(picked(key)).centerLeft + const Offset(AppSpacing.lg, 0),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the aroma question: the search under the question, six chips '
      'under each heading, no check mark, any number of aromas', (
    tester,
  ) async {
    final flow = flowAt(SensoryPage.nose);
    await pump(tester, flow);

    for (final (index, group) in menu.groups.indexed) {
      expect(find.text(group.title), findsOneWidget);
      for (final each in group.chips.take(6)) {
        expect(chip(each.key), findsOneWidget);
        expect(find.text('${each.emoji} ${each.label}'), findsOneWidget);
      }
      // The rest wait behind the heading, which says how many they are.
      for (final each in group.chips.skip(6)) {
        expect(chip(each.key), findsNothing);
      }
      expect(
        find.descendant(
          of: find.byKey(ValueKey('aroma-section:$index')),
          matching: find.text('+${group.chips.length - 6}'),
        ),
        findsOneWidget,
      );
    }
    // The search sits right under the description, above the first group.
    // No count: any number of aromas is taken.
    expect(find.text('잔에서 어떤 향이 느껴졌나요?'), findsOneWidget);
    const description = '코로 느낀 첫인상들을 골라 보세요.';
    expect(find.text(description), findsOneWidget);
    expect(find.textContaining('/5'), findsNothing);
    final search = find.byKey(const ValueKey('aroma-search:open'));
    expect(search, findsOneWidget);
    expect(
      tester.getTopLeft(search).dy,
      greaterThan(tester.getBottomLeft(find.text(description)).dy),
    );
    expect(
      tester.getBottomLeft(search).dy,
      lessThan(tester.getTopLeft(find.text(menu.groups.first.title)).dy),
    );
    // Nothing is picked yet, so there is no bar.
    expect(find.byKey(const ValueKey('aroma-picked')), findsNothing);

    // 다음 waits for a pick; SKIP in the header is the way past the page.
    expect(nextButton(tester).onPressed, isNull);

    // Every chip shown may be picked: nothing is refused.
    final keys = [
      for (final group in menu.groups)
        for (final each in group.chips.take(6)) each.key,
    ];
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
    // The bar holds them all on one line, in the order picked.
    expect(bar(tester), [for (final key in keys) word(key)]);
    expect(
      tester.getSize(find.byKey(const ValueKey('aroma-picked'))).height,
      lessThan(56),
    );
    // Two equal columns: chips in one row share the same width.
    final firstTwo = menu.groups.first.chips.take(2).toList();
    expect(
      tester.getSize(chip(firstTwo[0].key)).width,
      tester.getSize(chip(firstTwo[1].key)).width,
    );

    await tap(tester, 'sensory-next');
    expect(flow.current, SensoryPage.palate);
  });

  testWidgets('a heading opens and closes its own chips, six at a time; a '
      'picked chip it hides stays in the bar', (tester) async {
    final flow = flowAt(SensoryPage.nose);
    await pump(tester, flow);

    final group = menu.groups.first;
    final hidden = group.chips.skip(6).toList();
    const heading = ValueKey('aroma-section:0');
    Finder inHeading(Finder matching) =>
        find.descendant(of: find.byKey(heading), matching: matching);
    double chevronTurns() => tester
        .widget<AnimatedRotation>(inHeading(find.byType(AnimatedRotation)))
        .turns;

    // The whole row is the button: wide, tall enough to touch, and it says
    // what a tap does.
    expect(
      tester.getSize(find.byKey(heading)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(heading)).width,
      tester.getSize(find.byType(AromaPicker)).width,
    );
    expect(find.bySemanticsLabel('${group.title} 향 모두 보기'), findsOneWidget);
    expect(chevronTurns(), 0);

    // A tap on the heading's word opens every chip of this heading alone,
    // in the menu's order.
    await tester.tap(find.text(group.title));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<AppChip>(
            find.byWidgetPredicate((widget) {
              final key = widget.key;
              return widget is AppChip &&
                  key is ValueKey<String> &&
                  key.value.startsWith('aroma:nose:');
            }),
          )
          .take(group.chips.length)
          .map((chip) => (chip.key! as ValueKey<String>).value),
      [for (final each in group.chips) 'aroma:nose:${each.key}'],
    );
    expect(inHeading(find.textContaining('+')), findsNothing);
    expect(chevronTurns(), .5);
    expect(find.bySemanticsLabel('${group.title} 향 접기'), findsOneWidget);
    expect(chip(menu.groups[1].chips[6].key), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('aroma-section:1')),
        matching: find.text('+${menu.groups[1].chips.length - 6}'),
      ),
      findsOneWidget,
    );

    // One of the opened chips is picked.
    final kept = hidden[3].key;
    await tap(tester, 'aroma:nose:$kept');

    // Closed again there are the first six and no more: the picked chip is
    // hidden with the rest, the count is what it was, and the bar keeps it.
    await tap(tester, 'aroma-section:0');
    expect(chevronTurns(), 0);
    for (final each in group.chips.take(6)) {
      expect(chip(each.key), findsOneWidget);
    }
    for (final each in hidden) {
      expect(chip(each.key), findsNothing);
    }
    expect(inHeading(find.text('+${hidden.length}')), findsOneWidget);
    expect(bar(tester), [word(kept)]);
    expect(flow.aromas(AromaStage.nose), {kept});

    // Its × unpicks it there, and with nothing picked the bar goes.
    await remove(tester, kept);
    expect(flow.aromas(AromaStage.nose), isEmpty);
    expect(find.byKey(const ValueKey('aroma-picked')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap picks an aroma and a second unpicks it; the bar names '
      'each, between the search and the menu, and only its × acts', (
    tester,
  ) async {
    final flow = flowAt(SensoryPage.nose);
    final [first, second] = menu.keys.take(2).toList();
    await pump(tester, flow);
    AppChip barChip(String key) => tester.widget<AppChip>(
      find.descendant(of: picked(key), matching: find.byType(AppChip)),
    );

    await tap(tester, 'aroma:nose:$first');
    await tap(tester, 'aroma:nose:$second');
    expect(flow.aromas(AromaStage.nose).toList(), [first, second]);
    // A picked aroma looks the same in the menu and in the bar.
    for (final key in [first, second]) {
      expect(tester.widget<AppChip>(chip(key)).selected, isTrue);
      expect(tester.widget<AppChip>(chip(key)).tone, AppChipTone.positive);
      expect(barChip(key).tone, AppChipTone.positive);
    }
    expect(bar(tester), [word(first), word(second)]);
    final strip = find.byKey(const ValueKey('aroma-picked'));
    expect(
      tester.getTopLeft(strip).dy,
      greaterThan(
        tester
            .getBottomLeft(find.byKey(const ValueKey('aroma-search:open')))
            .dy,
      ),
    );
    expect(
      tester.getBottomLeft(strip).dy,
      lessThan(tester.getTopLeft(find.text(menu.groups.first.title)).dy),
    );

    // A second tap unpicks.
    await tap(tester, 'aroma:nose:$first');
    expect(flow.aromas(AromaStage.nose), {second});
    expect(tester.widget<AppChip>(chip(first)).selected, isFalse);
    expect(bar(tester), [word(second)]);

    // A touch on a bar chip's name does nothing; its × unpicks.
    await tapBarChipBody(tester, second);
    expect(flow.aromas(AromaStage.nose), {second});
    expect(
      tester
          .getSize(
            find.descendant(
              of: picked(second),
              matching: find.bySemanticsLabel('${word(second)} 빼기'),
            ),
          )
          .shortestSide,
      greaterThanOrEqualTo(44),
    );
    await remove(tester, second);
    expect(flow.aromas(AromaStage.nose), isEmpty);
    expect(find.byKey(const ValueKey('aroma-picked')), findsNothing);
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

    // 다음 on the palate: the second tap would leave the finish unread.
    final byNext = flowAt(SensoryPage.palate)..chooseLevel('body', 3);
    await pump(tester, byNext);
    await doubleTap(find.byKey(const ValueKey('sensory-next')));
    expect(byNext.current, SensoryPage.finish);
    // Once the question has settled, 다음 answers again.
    await tap(tester, 'sensory-next');
    expect(byNext.current, SensoryPage.review);

    // SKIP on 재음용 의사: the second tap would skip the nose unread.
    final bySkip = registry.createFlow(redWine);
    await pump(tester, bySkip);
    await doubleTap(find.text('SKIP'));
    expect(bySkip.current, SensoryPage.nose);
    expect(bySkip.noseSkipped, isFalse);
  });

  Finder gaugeLabel(String axis, String text) => find.descendant(
    of: find.byKey(ValueKey('gauge-label:$axis')),
    matching: find.text(text, findRichText: true),
  );

  Finder knob(String axis) => find.byKey(ValueKey('gauge-knob:$axis'));

  /// Where a stop of a gauge stands: the middle of its column, or for the
  /// end columns, which reach the row's edges, one even step out from the
  /// stops beside them.
  Offset stop(WidgetTester tester, String axis, int step) {
    Offset middle(int at) =>
        tester.getCenter(find.byKey(ValueKey('gauge:$axis:$at')));
    final gap = middle(3) - middle(2);
    return switch (step) {
      1 => middle(2) - gap,
      5 => middle(4) + gap,
      _ => middle(step),
    };
  }

  testWidgets('a gauge row says 선택해 주세요 until a stop is tapped, then the '
      'step\'s term and hint; a tap on the chosen stop clears it', (
    tester,
  ) async {
    final flow = flowAt(SensoryPage.palate);
    await pump(tester, flow);
    expect(find.text('입안에서 느껴진 맛과 질감은 어땠나요?'), findsOneWidget);
    expect(find.text('입안에서 느껴진 인상을 가볍게 선택해 보세요.'), findsOneWidget);

    // A red wine: its tannin, not its bubbles. Each row has five stops, at
    // least a tap target high, with no number on them and no knob: nothing
    // is chosen for the reader.
    for (final (axis, label) in [
      ('sweetness', '당도'),
      ('acidity', '산미'),
      ('body', '바디감'),
      ('tannin', '타닌'),
    ]) {
      expect(find.text(label), findsOneWidget);
      expect(gaugeLabel(axis, '선택해 주세요'), findsOneWidget);
      for (var step = 1; step <= 5; step++) {
        final column = find.byKey(ValueKey('gauge:$axis:$step'));
        expect(column, findsOneWidget);
        expect(
          tester.getSize(column).height,
          greaterThanOrEqualTo(AppSizes.minimumTapTarget),
        );
        expect(find.text('$step'), findsNothing);
      }
      expect(knob(axis), findsNothing);
    }
    // The stops stand evenly apart, and under the track's ends are the
    // words of its first and last steps.
    expect(
      stop(tester, 'body', 4).dx - stop(tester, 'body', 3).dx,
      closeTo(stop(tester, 'body', 3).dx - stop(tester, 'body', 2).dx, .01),
    );
    final body = redWine.palate.firstWhere((gauge) => gauge.axis == 'body');
    final low = find.text(body.levelAt(1).term);
    final high = find.text(body.levelAt(5).term);
    expect(low, findsOneWidget);
    expect(high, findsOneWidget);
    expect(tester.getTopLeft(low).dx, lessThan(stop(tester, 'body', 2).dx));
    expect(
      tester.getTopRight(high).dx,
      greaterThan(stop(tester, 'body', 4).dx),
    );
    expect(tester.getTopLeft(low).dy, greaterThan(stop(tester, 'body', 1).dy));
    expect(find.byKey(const ValueKey('gauge:sparkling:1')), findsNothing);
    expect(find.byKey(const ValueKey('gauge:bitterness:1')), findsNothing);

    await tap(tester, 'gauge:sweetness:2');
    expect(flow.level('sweetness'), 2);
    expect(gaugeLabel('sweetness', '드라이 · 산뜻한 기본 드라이'), findsOneWidget);
    expect(gaugeLabel('sweetness', '선택해 주세요'), findsNothing);
    // The knob sits on the stop tapped.
    expect(
      tester.getCenter(knob('sweetness')).dx,
      closeTo(stop(tester, 'sweetness', 2).dx, .01),
    );
    // The other rows still wait.
    expect(gaugeLabel('acidity', '선택해 주세요'), findsOneWidget);
    expect(knob('acidity'), findsNothing);

    await tap(tester, 'gauge:sweetness:4');
    expect(flow.level('sweetness'), 4);
    expect(gaugeLabel('sweetness', '세미 스위트 · 기분 좋은 달콤함'), findsOneWidget);
    expect(knob('sweetness'), findsOneWidget);

    await tap(tester, 'gauge:sweetness:4');
    expect(flow.level('sweetness'), isNull);
    expect(gaugeLabel('sweetness', '선택해 주세요'), findsOneWidget);
    expect(knob('sweetness'), findsNothing);

    // To a screen reader the track is a slider named by its axis: a step
    // up from nothing is the first stop, a step down from it clears.
    final sweetness = redWine.palate.firstWhere(
      (gauge) => gauge.axis == 'sweetness',
    );
    Semantics sliderOf() => tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.slider == true &&
            widget.properties.label == sweetness.label,
      ),
    );
    String? value() => sliderOf().properties.value;
    expect(value(), '선택 안 함');
    expect(sliderOf().properties.onDecrease, isNull);
    sliderOf().properties.onIncrease!();
    await tester.pumpAndSettle();
    expect(flow.level('sweetness'), 1);
    expect(value(), sweetness.levelAt(1).term);
    sliderOf().properties.onIncrease!();
    await tester.pumpAndSettle();
    expect(flow.level('sweetness'), 2);
    expect(value(), sweetness.levelAt(2).term);
    sliderOf().properties.onDecrease!();
    await tester.pumpAndSettle();
    expect(flow.level('sweetness'), 1);
    sliderOf().properties.onDecrease!();
    await tester.pumpAndSettle();
    expect(flow.level('sweetness'), isNull);
    expect(value(), '선택 안 함');
    // Left empty, the page still moves on.
    expect(nextButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a drag along a gauge moves the knob from stop to stop and the '
      'label with it; it never clears the gauge, and a drag up or down '
      'chooses nothing', (tester) async {
    final flow = flowAt(SensoryPage.palate);
    await pump(tester, flow);
    final acidity = redWine.palate.firstWhere(
      (gauge) => gauge.axis == 'acidity',
    );
    Future<void> expectAt(int step) async {
      await tester.pumpAndSettle();
      expect(flow.level('acidity'), step);
      expect(
        gaugeLabel('acidity', acidity.levelAt(step).label),
        findsOneWidget,
      );
      expect(
        tester.getCenter(knob('acidity')).dx,
        closeTo(stop(tester, 'acidity', step).dx, .01),
      );
    }

    // From nothing chosen, the knob lands on the stop the drag starts by.
    final second = stop(tester, 'acidity', 2);
    final third = stop(tester, 'acidity', 3);
    final fourth = stop(tester, 'acidity', 4);
    final drag = await tester.startGesture(second);
    await drag.moveBy(const Offset(24, 0));
    await expectAt(2);
    // It snaps to the nearest stop: short of half way it stays, past half
    // way it moves on, and the label follows while the finger is down.
    await drag.moveTo(Offset.lerp(second, third, .4)!);
    await expectAt(2);
    await drag.moveTo(Offset.lerp(third, fourth, .7)!);
    await expectAt(4);
    // Moving on over the stop it holds does not clear it.
    await drag.moveTo(fourth + const Offset(3, 0));
    await drag.moveTo(fourth - const Offset(3, 0));
    await expectAt(4);
    // Past the end of the track is its last stop.
    await drag.moveBy(const Offset(600, 0));
    await expectAt(5);
    await drag.up();
    await expectAt(5);
    // The knob on an end stop stays inside the row.
    expect(
      tester.getRect(knob('acidity')).right,
      closeTo(
        tester.getRect(find.byKey(const ValueKey('gauge:acidity:5'))).right,
        .01,
      ),
    );

    // A drag that starts and ends by the knob leaves it there.
    final held = await tester.startGesture(stop(tester, 'acidity', 5));
    await held.moveBy(const Offset(-24, 0));
    await held.up();
    await expectAt(5);

    // Up and down belongs to the page: nothing is chosen.
    final scroll = await tester.startGesture(stop(tester, 'body', 3));
    await scroll.moveBy(const Offset(0, -60));
    await scroll.up();
    await tester.pumpAndSettle();
    expect(flow.level('body'), isNull);
    expect(knob('body'), findsNothing);
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
                  key.value.startsWith('gauge-label:');
            }),
          )
          .map(
            (widget) => (widget.key! as ValueKey<String>).value.substring(12),
          );
      expect(shown, axes);
      for (final gauge in gauges.palate) {
        expect(find.text(gauge.label), findsOneWidget);
      }
    });
  }

  /// The keys of the aroma chips the picker of [stage] shows, in order.
  List<String> shownChips(WidgetTester tester, String stage) => [
    for (final chip in tester.widgetList<AppChip>(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return widget is AppChip &&
            key is ValueKey<String> &&
            key.value.startsWith('aroma:$stage:');
      }),
    ))
      (chip.key! as ValueKey<String>).value.substring('aroma:$stage:'.length),
  ];

  const earlierTitle = '앞에서 고른 향';
  const frequentTitle = '자주 느끼는 향';
  const listHeading = ValueKey('aroma-section:0');
  Finder inListHeading(Finder matching) =>
      find.descendant(of: find.byKey(listHeading), matching: matching);

  testWidgets('under its gauges the palate shows one short list of the kind '
      'in the menu\'s place: six aromas, the rest behind +N', (tester) async {
    final flow = flowAt(SensoryPage.palate);
    await pump(tester, flow);
    final list = [for (final chip in menu.palateShortList) chip.key];
    expect(list, hasLength(12));

    // The gauges, the question, then the picker: its search and one list.
    const flavorTitle = '입안에서 느낀 향들을 선택해주세요.';
    expect(
      tester.getTopLeft(find.text(flavorTitle)).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const ValueKey('gauge:tannin:1'))).dy,
      ),
    );
    expect(find.byType(AromaPicker), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(AromaPicker)).dy,
      greaterThan(tester.getBottomLeft(find.text(flavorTitle)).dy),
    );
    expect(find.byKey(const ValueKey('aroma-search:open')), findsOneWidget);
    expect(find.byKey(const ValueKey('aroma-picked')), findsNothing);
    expect(find.text(frequentTitle), findsOneWidget);
    // There is one list; earlier picks get no group of their own.
    expect(find.text(earlierTitle), findsNothing);
    for (final group in menu.groups) {
      expect(find.text(group.title), findsNothing);
    }
    expect(shownChips(tester, 'palate'), list.take(6));
    final first = menu.palateShortList.first;
    expect(find.text('${first.emoji} ${first.label}'), findsOneWidget);
    expect(inListHeading(find.text('+6')), findsOneWidget);

    // The whole heading row opens the rest, in the list's order, and closes
    // them again; the first six never move.
    expect(
      tester.getSize(find.byKey(listHeading)).width,
      tester.getSize(find.byType(AromaPicker)).width,
    );
    expect(find.bySemanticsLabel('$frequentTitle 모두 보기'), findsOneWidget);
    await tap(tester, 'aroma-section:0');
    expect(shownChips(tester, 'palate'), list);
    expect(inListHeading(find.textContaining('+')), findsNothing);
    expect(find.bySemanticsLabel('$frequentTitle 접기'), findsOneWidget);
    await tap(tester, 'aroma:palate:${list.last}');
    await tap(tester, 'aroma-section:0');
    expect(shownChips(tester, 'palate'), list.take(6));
    expect(inListHeading(find.text('+6')), findsOneWidget);
    // A pick the closed list hides stays in the bar.
    expect(flow.aromas(AromaStage.palate), {list.last});
    expect(bar(tester), [word(list.last)]);

    // The search sheet still offers the menu's hidden aromas before a word
    // is typed.
    await tap(tester, 'aroma-search:open');
    expect(find.text('자주 찾는 ${menu.label} 향'), findsOneWidget);
    await tap(tester, 'aroma-search:done');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a list of eleven shows six and +5', (tester) async {
    final takju = OnboardingAromaMenu.forDrink('korean_traditional', 'takju');
    expect(takju.palateShortList, hasLength(11));
    expect(takju.finishShortList, hasLength(11));
    final gauges = gaugesFor('korean_traditional', 'takju');
    await pump(tester, flowAt(SensoryPage.palate, gauges), aromaMenu: takju);
    expect(shownChips(tester, 'palate'), [
      for (final chip in takju.palateShortList.take(6)) chip.key,
    ]);
    expect(inListHeading(find.text('+5')), findsOneWidget);
    await pump(tester, flowAt(SensoryPage.finish, gauges), aromaMenu: takju);
    expect(shownChips(tester, 'finish'), [
      for (final chip in takju.finishShortList.take(6)) chip.key,
    ]);
    expect(inListHeading(find.text('+5')), findsOneWidget);
  });

  testWidgets('the aromas picked before lead the one list and are not '
      'picked here until tapped; the list names each aroma once', (
    tester,
  ) async {
    // 자두 is the second of the palate's list, 오크 is not in it, and the
    // last was found by search: no menu has a chip for it.
    final searched = registry.aromaKeys.firstWhere(
      (key) => OnboardingAromaMenu.chipOf(key) == null,
    );
    final flow = registry.createFlow(redWine)
      ..setRevisit(RevisitIntent.wantAgain)
      ..next()
      ..toggleAroma(AromaStage.nose, 'plum')
      ..toggleAroma(AromaStage.nose, 'oak')
      ..toggleAroma(AromaStage.nose, searched)
      ..next();
    await pump(tester, flow);
    final palate = [for (final chip in menu.palateShortList) chip.key];
    expect(palate.take(7), [
      'black_cherry',
      'plum',
      'vanilla',
      'pepper',
      'mocha',
      'herbal',
      'raspberry',
    ]);

    // One list under one heading: the nose's picks, in the order picked,
    // then the kind's list without 자두. Six show; the other eight are
    // behind the heading.
    expect(find.text(earlierTitle), findsNothing);
    expect(find.text(frequentTitle), findsOneWidget);
    expect(shownChips(tester, 'palate'), [
      'plum',
      'oak',
      searched,
      'black_cherry',
      'vanilla',
      'pepper',
    ]);
    expect(inListHeading(find.text('+8')), findsOneWidget);
    // A chip says its emoji and word; one found by search, its word alone.
    expect(find.text('🍑 자두'), findsOneWidget);
    expect(find.text(word(searched)), findsOneWidget);

    // Nothing is answered on the reader's behalf.
    for (final key in ['plum', 'oak', searched]) {
      expect(tester.widget<AppChip>(chip(key, 'palate')).selected, isFalse);
      expect(chip(key), findsNothing);
    }
    expect(flow.aromas(AromaStage.palate), isEmpty);
    expect(find.byKey(const ValueKey('aroma-picked')), findsNothing);

    // A tap picks it for the palate alone, like any chip; nothing moves.
    await tap(tester, 'aroma:palate:plum');
    await tap(tester, 'aroma:palate:vanilla');
    expect(flow.aromas(AromaStage.palate), {'plum', 'vanilla'});
    expect(flow.aromas(AromaStage.nose), {'plum', 'oak', searched});
    expect(tester.widget<AppChip>(chip('plum', 'palate')).selected, isTrue);
    expect(bar(tester), [word('plum'), word('vanilla')]);
    expect(picked('plum', 'palate'), findsOneWidget);
    expect(shownChips(tester, 'palate').take(4), [
      'plum',
      'oak',
      searched,
      'black_cherry',
    ]);
    // Opened, the list still leaves the earlier pick out.
    await tap(tester, 'aroma-section:0');
    expect(shownChips(tester, 'palate').skip(3), [
      for (final key in palate)
        if (key != 'plum') key,
    ]);

    // The finish: its two gauges, then the nose's picks and the palate's,
    // each once, over the finish's own list without 오크.
    await tap(tester, 'sensory-next');
    expect(flow.current, SensoryPage.finish);
    expect(find.text('삼킨 뒤 남는 여운은 어땠나요?'), findsOneWidget);
    expect(find.text('목 넘김 뒤에 남은 느낌을 가볍게 선택해 보세요.'), findsOneWidget);
    expect(gaugeLabel('finish_length', '선택해 주세요'), findsOneWidget);
    expect(find.text('드라이·미네랄'), findsOneWidget);
    expect(find.text('과실·오크 풍미'), findsOneWidget);
    await tap(tester, 'gauge:finish_length:4');
    await tap(tester, 'gauge:finish_character:3');
    expect(gaugeLabel('finish_length', '미디엄 롱 · 향긋함이 은은하고 길게 남음'), findsOne);
    expect(gaugeLabel('finish_character', '밸런스'), findsOneWidget);

    const finishTitle = '삼킨 뒤 느껴지는 향들을 선택해주세요.';
    expect(find.text(finishTitle), findsOneWidget);
    expect(find.byType(AromaPicker), findsOneWidget);
    expect(find.byKey(const ValueKey('aroma-picked')), findsNothing);
    // The lead group of the gauge file is gone.
    expect(find.text('여운에 자주 남는 향'), findsNothing);
    expect(find.text(earlierTitle), findsNothing);
    expect(
      tester.getTopLeft(find.text(frequentTitle)).dy,
      greaterThan(tester.getBottomLeft(find.text(finishTitle)).dy),
    );
    final finish = [for (final chip in menu.finishShortList) chip.key];
    expect(finish.first, 'oak');
    expect(shownChips(tester, 'finish'), [
      'plum',
      'oak',
      searched,
      'vanilla',
      ...finish.skip(1).take(2),
    ]);
    expect(inListHeading(find.text('+9')), findsOneWidget);
    for (final group in menu.groups) {
      expect(find.text(group.title), findsNothing);
    }

    // An earlier pick tapped here is picked at the finish alone.
    await tap(tester, 'aroma:finish:oak');
    expect(flow.aromas(AromaStage.finish), {'oak'});
    expect(flow.aromas(AromaStage.palate), {'plum', 'vanilla'});
    expect(bar(tester), [word('oak')]);
    await tap(tester, 'aroma:finish:oak');
    expect(flow.aromas(AromaStage.finish), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('earlier picks that are in the list move to its front; the '
      'list keeps its length', (tester) async {
    final list = [for (final chip in menu.palateShortList) chip.key];
    final flow = registry.createFlow(redWine)
      ..setRevisit(RevisitIntent.wantAgain)
      ..next();
    for (final key in list.skip(6)) {
      flow.toggleAroma(AromaStage.nose, key);
    }
    flow.next();
    await pump(tester, flow);
    expect(shownChips(tester, 'palate'), list.skip(6));
    expect(inListHeading(find.text('+6')), findsOneWidget);
    await tap(tester, 'aroma-section:0');
    expect(shownChips(tester, 'palate'), [...list.skip(6), ...list.take(6)]);
    expect(tester.takeException(), isNull);
  });

  test('every short list holds aromas of the dictionary, each once, under '
      'the dictionary\'s word', () {
    for (final (category, style) in [
      ('wine', 'red_wine'),
      ('wine', 'white_wine'),
      ('wine', 'rose_wine'),
      ('whisky', 'single_malt_whisky'),
      ('whisky', 'bourbon'),
      ('korean_traditional', 'takju'),
      ('korean_traditional', 'yakju'),
      ('korean_traditional', 'distilled_soju'),
      ('korean_traditional', 'korean_fruit_wine'),
      ('sake', null),
    ]) {
      final menu = OnboardingAromaMenu.forDrink(category, style);
      for (final list in [menu.palateShortList, menu.finishShortList]) {
        final keys = [for (final chip in list) chip.key];
        expect(keys.length, anyOf(11, 12), reason: '$category $style');
        expect(keys.toSet(), hasLength(keys.length), reason: '$style');
        expect(registry.aromaKeys, containsAll(keys), reason: '$style');
        expect(engine.selectableKeys, containsAll(keys), reason: '$style');
        for (final chip in list) {
          expect(chip.label, word(chip.key));
          expect(chip.emoji, isNotEmpty);
          expect(OnboardingAromaMenu.chipOf(chip.key), same(chip));
        }
      }
    }
  });

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
      ..next()
      ..chooseLevel('finish_length', 4)
      ..chooseLevel('finish_character', 3)
      ..toggleAroma(AromaStage.finish, 'oak')
      ..next();
    var completed = 0;
    await pump(tester, flow, complete: () => completed++);

    expect(find.text('고르신 것들 중 아쉬웠던 부분이 있나요?'), findsOneWidget);
    expect(
      find.text('없다면 바로 저장을 눌러주세요 · 체크한 요소는 다음 추천에서 피해드려요'),
      findsOneWidget,
    );
    expect(find.text('SKIP'), findsNothing);
    expect(nextButton(tester).label, '저장');

    // The four groups, top to bottom, each with its answers as chips.
    final groups = {
      'nose': ('코로 맡은 향', ['aroma:nose:$first']),
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
      expect(
        find.descendant(of: section, matching: find.text(title)),
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
    // An aroma by its name; a gauge by its axis and the step's term.
    // An aroma keeps the emoji of its menu chip.
    expect(
      reviewChip(tester, 'aroma:nose:$first').label,
      '${OnboardingAromaMenu.chipOf(first)!.emoji} ${word(first)}',
    );
    expect(reviewChip(tester, 'level:sweetness').label, '당도 · 드라이');
    expect(reviewChip(tester, 'level:tannin').label, '타닌 · 퍼미');
    expect(reviewChip(tester, 'level:finish_length').label, '여운의 길이 · 미디엄 롱');
    expect(reviewChip(tester, 'level:finish_character').label, '끝맛의 인상 · 밸런스');
    expect(
      reviewChip(tester, 'aroma:finish:oak').label,
      '${OnboardingAromaMenu.chipOf('oak')!.emoji} ${word('oak')}',
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
    expect(find.bySemanticsLabel('타닌 · 퍼미, 아쉬웠던 부분으로 표시됨'), findsOneWidget);
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

  testWidgets('a group with nothing answered is left out of the review, '
      'heading and all', (tester) async {
    final flow = flowAt(SensoryPage.palate)..chooseLevel('body', 5);
    flow
      ..next()
      ..next();
    expect(flow.current, SensoryPage.review);
    await pump(tester, flow);
    expect(find.byKey(const ValueKey('review-section:palate')), findsOneWidget);
    expect(find.text('맛 · 질감'), findsOneWidget);
    for (final (name, title) in [
      ('nose', '코로 맡은 향'),
      ('flavor', '입안에서 퍼진 풍미'),
      ('finish', '여운'),
    ]) {
      expect(find.byKey(ValueKey('review-section:$name')), findsNothing);
      expect(find.text(title), findsNothing);
    }
    expect(find.byType(AppChip), findsOneWidget);
    expect(reviewChip(tester, 'level:body').label, '바디감 · 풀 바디');
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
    // The record's nose aroma leads the palate's short list, not picked.
    expect(find.text('앞에서 고른 향'), findsNothing);
    expect(find.text('자주 느끼는 향'), findsOneWidget);
    expect(
      tester.widget<AppChip>(chip(menu.keys.first, 'palate')).selected,
      isFalse,
    );
    expect(flow.aromas(AromaStage.palate), isEmpty);

    await tap(tester, 'gauge:acidity:1');
    expect(nextButton(tester).label, '다음');
    await tap(tester, 'sensory-next');
    expect(completed, 0);
    expect(nextButton(tester).label, '저장');
    // The nose's aroma belongs to another part.
    expect(find.byKey(const ValueKey('review-section:nose')), findsNothing);
    expect(reviewChip(tester, 'level:acidity').label, '산미 · 로우');
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
    // The whole flow: the nose skipped and the palate left empty.
    final flow = flowAt(SensoryPage.palate);
    await pump(tester, flow);
    expect(note, findsNothing);
    await tap(tester, 'sensory-next');
    expect(flow.current, SensoryPage.finish);
    expect(note, findsOneWidget);
    expect(nextButton(tester).onPressed, isNull);
    await tap(tester, 'gauge:finish_length:3');
    expect(note, findsNothing);
    expect(nextButton(tester).onPressed, isNotNull);
    await tap(tester, 'gauge:finish_length:3');
    expect(note, findsOneWidget);
    expect(nextButton(tester).onPressed, isNull);

    // A part asked again: the record's only answer cannot be taken away.
    var completed = 0;
    final part = registry.createFlow(redWine, only: SensoryPart.palate)
      ..chooseLevel('body', 3);
    await pump(tester, part, complete: () => completed++);
    expect(note, findsNothing);
    await tap(tester, 'gauge:body:3');
    expect(part.level('body'), isNull);
    expect(note, findsOneWidget);
    expect(nextButton(tester).label, '완료');
    expect(nextButton(tester).onPressed, isNull);
    expect(completed, 0);
    expect(tester.takeException(), isNull);
  });

  Future<Finder> openAromaSearch(WidgetTester tester) async {
    await tap(tester, 'aroma-search:open');
    return find.byKey(const ValueKey('sensory-aroma-search'));
  }

  testWidgets('aroma search opens in a sheet; what it finds is picked as a '
      'chip is and joins the bar', (tester) async {
    final flow = flowAt(SensoryPage.nose);
    await pump(tester, flow);
    expect(find.byKey(const ValueKey('sensory-aroma-search')), findsNothing);
    final search = await openAromaSearch(tester);
    expect(search, findsOneWidget);
    Finder found(String key) => find.byKey(ValueKey('search:aroma:nose:$key'));
    expect(
      find.descendant(of: search, matching: find.text('향·계열로 검색 (예: 곡물, 달콤)')),
      findsOneWidget,
    );
    // Before anything is typed the sheet offers the chips the menu keeps
    // behind its headings, a heading at a time.
    expect(find.text('자주 찾는 레드 와인 향'), findsOneWidget);
    final hidden = [for (final group in menu.groups) group.chips[6]];
    for (final chip in hidden) {
      expect(
        tester.widget<AppChip>(found(chip.key)).label,
        contains(chip.label),
      );
    }
    expect(found(menu.groups.last.chips[8].key), findsNothing);
    expect(found(menu.groups.first.chips[5].key), findsNothing);
    await tap(tester, 'search:aroma:nose:${hidden.first.key}');
    expect(flow.aromas(AromaStage.nose), {hidden.first.key});
    expect(tester.widget<AppChip>(found(hidden.first.key)).selected, isTrue);
    await tap(tester, 'search:aroma:nose:${hidden.first.key}');
    expect(flow.aromas(AromaStage.nose), isEmpty);
    // What is typed is searched for: the aromas found are chips in the
    // engine's order, several to a row, with nothing written beside them.
    final family = word('dried_fruit');
    await tester.enterText(search, family);
    await tester.pumpAndSettle();
    expect(find.text('자주 찾는 레드 와인 향'), findsNothing);
    final results = find.byKey(const ValueKey('aroma-search-results'));
    final ranked = engine.search(family);
    expect(ranked.first.key, 'dried_fruit');
    expect(ranked.map((result) => result.key), contains('raisin'));
    expect(
      tester
          .widgetList<AppChip>(
            find.descendant(of: results, matching: find.byType(AppChip)),
          )
          .map((chip) => (chip.key! as ValueKey<String>).value),
      [for (final result in ranked) 'search:aroma:nose:${result.key}'],
    );
    expect(
      tester
          .widgetList<Text>(
            find.descendant(of: results, matching: find.byType(Text)),
          )
          .map((text) => text.data),
      [for (final result in ranked) result.label],
    );
    expect(
      tester.getTopLeft(found(ranked[1].key)).dy,
      tester.getTopLeft(found(ranked[0].key)).dy,
    );
    expect(
      tester.getTopLeft(found(ranked[1].key)).dx,
      greaterThan(tester.getTopRight(found(ranked[0].key)).dx),
    );

    await tester.enterText(search, extra);
    await tester.pumpAndSettle();
    // The chip found is touched as the question's chips are: picked, then
    // unpicked. The sheet stays open, with what was typed, and shows the
    // question's bar.
    await tap(tester, 'search:aroma:nose:$extra');
    expect(flow.aromas(AromaStage.nose), {extra});
    expect(tester.widget<AppChip>(found(extra)).tone, AppChipTone.positive);
    expect(find.text(extra), findsOneWidget);
    final sheetBar = find.byKey(const ValueKey('search:aroma-picked'));
    expect(
      find.descendant(of: sheetBar, matching: find.text(word(extra))),
      findsOneWidget,
    );
    await tap(tester, 'search:aroma:nose:$extra');
    expect(flow.aromas(AromaStage.nose), isEmpty);
    expect(sheetBar, findsNothing);
    await tap(tester, 'search:aroma:nose:$extra');
    expect(flow.aromas(AromaStage.nose), {extra});
    await tap(tester, 'aroma-search:done');
    expect(search, findsNothing);
    // The menu has no chip for it; the bar holds it.
    expect(chip(extra), findsNothing);
    expect(bar(tester), [word(extra)]);

    // An aroma the menu keeps behind a heading, found by search, joins the
    // bar; its heading stays as it was. The × of the sheet's bar unpicks as
    // the question's does.
    final group = menu.groups.last;
    final kept = group.chips.last;
    await tester.enterText(await openAromaSearch(tester), kept.label);
    await tester.pumpAndSettle();
    await tap(tester, 'search:aroma:nose:${kept.key}');
    expect(flow.aromas(AromaStage.nose), {extra, kept.key});
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('search:picked:aroma:nose:${kept.key}')),
        matching: find.bySemanticsLabel('${word(kept.key)} 빼기'),
      ),
    );
    await tester.pumpAndSettle();
    expect(flow.aromas(AromaStage.nose), {extra});
    expect(tester.widget<AppChip>(found(kept.key)).selected, isFalse);
    await tap(tester, 'search:aroma:nose:${kept.key}');
    await tap(tester, 'aroma-search:done');
    expect(flow.aromas(AromaStage.nose).toList(), [extra, kept.key]);
    expect(bar(tester), [word(extra), kept.label]);
    expect(chip(kept.key), findsNothing);
    final last = ValueKey('aroma-section:${menu.groups.length - 1}');
    expect(
      find.descendant(
        of: find.byKey(last),
        matching: find.text('+${group.chips.length - 6}'),
      ),
      findsOneWidget,
    );
    // Opened, the heading shows it picked.
    await tap(tester, 'aroma-section:${menu.groups.length - 1}');
    expect(tester.widget<AppChip>(chip(kept.key)).selected, isTrue);
    expect(tester.widget<AppChip>(chip(kept.key)).tone, AppChipTone.positive);

    await remove(tester, extra);
    expect(flow.aromas(AromaStage.nose), {kept.key});
    await tap(tester, 'sensory-next');
    expect(flow.current, SensoryPage.palate);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aroma search says so when no aroma has the name', (
    tester,
  ) async {
    final flow = flowAt(SensoryPage.nose);
    await pump(tester, flow);
    final search = await openAromaSearch(tester);
    await tester.enterText(search, 'zzzz-no-such-aroma');
    await tester.pumpAndSettle();
    expect(find.text('일치하는 향을 찾지 못했어요.\n다른 단어로 검색해 보세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('aroma-search-results')), findsNothing);
    expect(flow.aromas(AromaStage.nose), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an aroma found by search joins however many the menu gave', (
    tester,
  ) async {
    final flow = flowAt(SensoryPage.nose);
    await pump(tester, flow);
    final menuPicks = menu.keys.take(6).toList();
    for (final key in menuPicks) {
      await tap(tester, 'aroma:nose:$key');
    }
    // The bar, wider than the screen by now, has followed the newest pick
    // to its end.
    expect(tester.getRect(picked(menuPicks.first)).left, lessThan(0));
    expect(
      tester.getRect(picked(menuPicks.last)).right,
      lessThanOrEqualTo(tester.view.physicalSize.width),
    );
    final search = await openAromaSearch(tester);
    await tester.enterText(search, extra);
    await tester.pumpAndSettle();
    await tap(tester, 'search:aroma:nose:$extra');
    expect(flow.aromas(AromaStage.nose), {...menuPicks, extra});
    await tap(tester, 'aroma-search:done');
    // A picked chip touched again is unpicked.
    await tap(tester, 'aroma:nose:${menuPicks.first}');
    expect(flow.aromas(AromaStage.nose), {...menuPicks.skip(1), extra});
    expect(bar(tester), [
      for (final key in [...menuPicks.skip(1), extra]) word(key),
    ]);
    expect(tester.takeException(), isNull);
  });
}
