import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/core/sensory/revisit_intent.dart';
import 'package:soolgyul/src/core/sensory/finish_choices.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/core/sensory/sensory_asked_keys.dart';
import 'package:soolgyul/src/core/sensory/sensory_question_flow.dart';
import 'package:soolgyul/src/core/sensory/taste_reactions.dart';
import 'package:soolgyul/src/features/onboarding/presentation/sensory/aroma_picker.dart';
import 'package:soolgyul/src/features/onboarding/presentation/sensory_questionnaire_screen.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';

import '../support/sensory_fixtures.dart';

void main() {
  final registry = sensoryRegistry();
  final engine = aromaEngine();
  final menu = OnboardingAromaMenu.forCategory('wine');
  // An aroma the menu has no chip for, reachable only through the search.
  final extra = registry.aromaKeys.firstWhere(
    (key) => !menu.keys.contains(key),
  );

  Future<void> pump(
    WidgetTester tester,
    SensoryQuestionFlow flow, {
    VoidCallback? complete,
    bool searchFirst = true,
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
            skip: skip,
            flow: flow,
            registry: registry,
            aromaMenu: menu,
            aromaEngine: engine,
            aromaSearchFirst: searchFirst,
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
    expect(find.text('맞는 표현이 없어요'), findsNothing);
    expect(find.text('어떤 느낌이었나요?'), findsNothing);
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

  testWidgets('the revisit question has no unsure option; SKIP stores it', (
    tester,
  ) async {
    final flow = registry.createFlow();
    await pump(tester, flow);
    expect(find.text('아직은 잘 모르겠어요'), findsNothing);
    expect(find.byKey(const ValueKey('revisit:unsure')), findsOneWidget);
    await tap(tester, 'revisit:unsure');
    expect(flow.revisit, RevisitIntent.unsure);
    expect(flow.current.section, SensorySection.aroma);
  });

  testWidgets('skippable questions show SKIP in the header, not the body', (
    tester,
  ) async {
    final flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    flow.next();
    await pump(tester, flow);

    expect(find.text('잘 모르겠어요'), findsNothing);
    expect(find.text('SKIP'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const ValueKey('aroma:unsure')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    // Tastes are always answered, so their page has no SKIP.
    expect(flow.current.section, SensorySection.taste);
    expect(find.text('SKIP'), findsNothing);
  });

  testWidgets('the aroma question: the search under the question, grouped '
      'chips, no check mark, any number of aromas; the first record has the '
      'search under the menu', (tester) async {
    final flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    flow.next();
    await pump(tester, flow);

    for (final group in menu.groups) {
      expect(find.text(group.title), findsOneWidget);
      for (final chip in group.chips) {
        expect(
          find.byKey(ValueKey('notice:aroma:${chip.key}')),
          findsOneWidget,
        );
        expect(find.text('${chip.emoji} ${chip.label}'), findsOneWidget);
      }
    }
    expect(find.byKey(const ValueKey('aroma-more')), findsNothing);
    // The description, then the tap guide; the search sits right under it,
    // above the first group. No count: any number of aromas is taken.
    expect(find.text('코로 느낀 첫인상들을 골라 보세요.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(AromaTapGuide.text)).dy,
      greaterThan(tester.getBottomLeft(find.text('코로 느낀 첫인상들을 골라 보세요.')).dy),
    );
    expect(find.text(AromaTapGuide.text), findsOneWidget);
    expect(find.textContaining('/5'), findsNothing);
    expect(find.text(aromaSearchInvitation), findsNothing);
    final search = find.byKey(const ValueKey('aroma-search:open'));
    expect(search, findsOneWidget);
    expect(
      tester.getTopLeft(search).dy,
      greaterThan(tester.getBottomLeft(find.text(AromaTapGuide.text)).dy),
    );
    expect(
      tester.getBottomLeft(search).dy,
      lessThan(tester.getTopLeft(find.text(menu.groups.first.title)).dy),
    );

    // 다음 waits for a pick; SKIP in the header is the way past the page.
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('sensory-next')))
          .onPressed,
      isNull,
    );

    // Every chip of the menu may be picked: nothing is refused.
    final keys = menu.keys.toList();
    for (final key in keys) {
      final chip = find.byKey(ValueKey('notice:aroma:$key'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }
    expect(keys.length, greaterThan(5));
    expect(flow.selected(SensorySection.aroma), keys.toSet());
    expect(find.byType(SnackBar), findsNothing);
    // Colour alone marks a picked chip; no check mark appears.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppChip && widget.leadingIcon != null,
      ),
      findsNothing,
    );
    // Two equal columns: chips in one row share the same width.
    final firstTwo = menu.groups.first.chips.take(2).toList();
    expect(
      tester
          .getSize(find.byKey(ValueKey('notice:aroma:${firstTwo[0].key}')))
          .width,
      tester
          .getSize(find.byKey(ValueKey('notice:aroma:${firstTwo[1].key}')))
          .width,
    );

    await tap(tester, 'sensory-next');
    // Aromas take no target or reason: the tastes come next.
    expect(flow.current.section, SensorySection.taste);
    expect(flow.current.page, SensoryPage.reaction);

    // The first record offers the search under the menu, asking whether a
    // finer aroma is wanted.
    final first = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    first.next();
    await pump(tester, first, searchFirst: false);
    final invitation = find.text(aromaSearchInvitation);
    final below = find.byKey(const ValueKey('aroma-search:open'));
    await tester.ensureVisible(below);
    await tester.pumpAndSettle();
    expect(invitation, findsOneWidget);
    expect(below, findsOneWidget);
    final lastChip = find.byKey(
      ValueKey('notice:aroma:${menu.groups.last.chips.last.key}'),
    );
    expect(
      tester.getTopLeft(invitation).dy,
      greaterThan(tester.getBottomLeft(lastChip).dy),
    );
    expect(
      tester.getTopLeft(below).dy,
      greaterThan(tester.getBottomLeft(invitation).dy),
    );
    // An aroma found there joins the chips under the box.
    await tester.tap(below);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sensory-aroma-search')),
      extra,
    );
    await tester.pumpAndSettle();
    await tap(tester, 'search:aroma:$extra');
    await tap(tester, 'aroma-search:done');
    expect(first.selected(SensorySection.aroma), {extra});
    final found = find.byKey(ValueKey('notice:aroma:$extra'));
    await tester.ensureVisible(found);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(found).dy,
      greaterThan(tester.getBottomLeft(below).dy),
    );
  });

  testWidgets('a double tap on 다음 or SKIP moves one question, not two', (
    tester,
  ) async {
    SensoryQuestionFlow atAroma() => registry.createFlow()
      ..setRevisit(RevisitIntent.wantAgain)
      ..next();
    // The tastes always need an answer, so the pages around them are
    // reached one at a time: aroma, then mouthfeel and the finish.
    SensoryQuestionFlow atMouthfeel() {
      final flow = atAroma()..next();
      for (final key in flow.askedTasteKeys) {
        flow.toggleReaction(SensorySection.taste, key, TasteReaction.liked);
      }
      return flow..next();
    }

    Future<void> doubleTap(Finder target) async {
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(target, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    // 다음 on the last question but one: the second tap would send the
    // record from the last question, unread.
    var completed = 0;
    final byNext = atMouthfeel();
    await pump(tester, byNext, complete: () => completed++);
    await doubleTap(find.byKey(const ValueKey('sensory-next')));
    expect(byNext.current.page, SensoryPage.finish);
    expect(completed, 0);
    // Once the question has settled, 다음 answers again.
    await tap(tester, 'sensory-next');
    expect(completed, 1);

    final bySkip = atMouthfeel();
    await pump(tester, bySkip, complete: () => completed++);
    await doubleTap(find.text('SKIP'));
    expect(bySkip.current.page, SensoryPage.finish);
    expect(bySkip.finish.unsure, isFalse);
    expect(completed, 1);
  });

  testWidgets(
    'a taste opens its reason chips in place, without character or unspecified',
    (tester) async {
      // Every taste shares the page body; one subject stands for all.
      const subject = 'acidity';
      final flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
      flow.next();
      await pump(tester, flow);
      await tap(tester, 'aroma:unsure');
      expect(
        find.byKey(ValueKey('reason:taste:$subject:gentle')),
        findsNothing,
      );
      for (final other in SensoryQuestionFlow.tasteKeys) {
        if (other == subject) continue;
        await tap(tester, 'reaction:taste:$other:disliked');
        expect(
          find.byKey(ValueKey('reason:taste:$other:gentle')),
          findsNothing,
        );
      }
      await tap(tester, 'reaction:taste:$subject:liked');
      expect(flow.current.page, SensoryPage.reaction);
      for (final retired in ['character', 'unspecified']) {
        expect(
          find.byKey(ValueKey('reason:taste:$subject:$retired')),
          findsNothing,
        );
      }
      // No reason is required.
      expect(flow.canContinue, isTrue);
      for (final reason in ['gentle', 'pronounced', 'harmony']) {
        await tap(tester, 'reason:taste:$subject:$reason');
      }
      // One reason at a time: each tap replaces the last, the same one clears.
      expect(flow.reasons(SensorySection.taste, subject), {'harmony'});
      await tap(tester, 'reason:taste:$subject:harmony');
      expect(flow.reasons(SensorySection.taste, subject), isEmpty);
      // 아쉬웠어요 swaps the chips for the burden reasons and drops the old ones.
      await tap(tester, 'reaction:taste:$subject:disliked');
      expect(flow.reasons(SensorySection.taste, subject), isEmpty);
      expect(
        find.byKey(ValueKey('reason:taste:$subject:gentle')),
        findsNothing,
      );
      for (final reason in ['too_strong', 'too_weak', 'disharmony']) {
        expect(
          find.byKey(ValueKey('reason:taste:$subject:$reason')),
          findsOneWidget,
        );
      }
      // A taste was liked or it was not: there is no middle answer.
      expect(
        find.byKey(ValueKey('reaction:taste:$subject:fine')),
        findsNothing,
      );
      await tap(tester, 'sensory-next');
      expect(flow.current.section, SensorySection.mouthfeel);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a white wine is not asked bitterness, tannin or bubbles', (
    tester,
  ) async {
    final flow = registry.createFlow(
      SensoryAskedKeys.forProduct('wine', 'white_wine'),
    )..setRevisit(RevisitIntent.wantAgain);
    flow.next();
    await pump(tester, flow);
    // Nothing picked, so 다음 waits; SKIP in the header moves on as unsure.
    await tap(tester, 'aroma:unsure');
    expect(flow.unsure(SensorySection.aroma), isTrue);
    expect(flow.current.section, SensorySection.taste);
    expect(
      find.byKey(const ValueKey('reaction:taste:acidity:liked')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('reaction:taste:bitterness:liked')),
      findsNothing,
    );
    // Both tastes asked must be answered before the page moves on.
    expect(flow.canContinue, isFalse);
    await tap(tester, 'reaction:taste:sweetness:liked');
    await tap(tester, 'reaction:taste:acidity:liked');
    await tap(tester, 'sensory-next');
    // A white wine is asked weight and warmth only, on one page.
    expect(find.text('무게감'), findsOne);
    expect(find.text('열감'), findsOne);
    expect(find.byKey(const ValueKey('judge:mouthfeel:light:liked')), findsOne);
    expect(
      find.byKey(const ValueKey('reaction:mouthfeel:heavy:fine')),
      findsNothing,
    );
    for (final key in ['smooth', 'drying', 'bubbles']) {
      expect(
        find.byKey(ValueKey('reaction:mouthfeel:$key:liked')),
        findsNothing,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a burden aroma goes straight to the tastes, no reason page', (
    tester,
  ) async {
    final flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    flow.next();
    await pump(tester, flow);
    const hint = ValueKey('aroma-second-tap-hint');
    expect(find.byKey(hint), findsNothing);
    await tap(tester, 'notice:aroma:cherry'); // liked
    // The first aroma picked says what a second tap does.
    expect(find.byKey(hint), findsOneWidget);
    await tap(tester, 'notice:aroma:cherry'); // a second tap: a burden
    expect(find.byKey(hint), findsNothing);
    expect(flow.reactions(SensorySection.aroma), {
      'cherry': TasteReaction.disliked,
    });
    // It is said once.
    final other = menu.keys.firstWhere((key) => key != 'cherry');
    await tap(tester, 'notice:aroma:$other');
    expect(find.byKey(hint), findsNothing);
    await tap(tester, 'notice:aroma:$other');
    await tap(tester, 'notice:aroma:$other');
    await tap(tester, 'sensory-next');
    expect(flow.current.section, SensorySection.taste);
    expect(flow.current.page, SensoryPage.reaction);
    expect(tester.takeException(), isNull);
  });

  Future<Finder> openAromaSearch(WidgetTester tester) async {
    await tap(tester, 'aroma-search:open');
    return find.byKey(const ValueKey('sensory-aroma-search'));
  }

  testWidgets('aroma search opens in a sheet and the choice joins the chips '
      'above the menu', (tester) async {
    final flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    flow.next();
    await pump(tester, flow);
    expect(find.byKey(const ValueKey('sensory-aroma-search')), findsNothing);
    expect(find.byKey(ValueKey('notice:aroma:$extra')), findsNothing);
    final search = await openAromaSearch(tester);
    expect(search, findsOneWidget);
    expect(find.text('기억나는 향을 검색창에 적어 보세요.'), findsOneWidget);
    await tester.enterText(search, extra);
    await tester.pumpAndSettle();
    await tap(tester, 'search:aroma:$extra');
    expect(flow.selected(SensorySection.aroma), {extra});
    // The chip found is touched as the question's chips are: liked, then a
    // burden, then off.
    expect(find.text(AromaTapGuide.text), findsWidgets);
    expect(flow.reactions(SensorySection.aroma), {extra: TasteReaction.liked});
    await tap(tester, 'search:aroma:$extra');
    expect(flow.reactions(SensorySection.aroma), {
      extra: TasteReaction.disliked,
    });
    await tap(tester, 'search:aroma:$extra');
    expect(flow.selected(SensorySection.aroma), isEmpty);
    await tap(tester, 'search:aroma:$extra');
    await tap(tester, 'aroma-search:done');
    expect(search, findsNothing);
    final chip = find.byKey(ValueKey('notice:aroma:$extra'));
    expect(chip, findsOneWidget);
    expect(
      tester.getBottomLeft(chip).dy,
      lessThan(tester.getTopLeft(find.text(menu.groups.first.title)).dy),
    );
    // Added from the search as liked; the chip's next tap makes it a burden.
    expect(flow.reactions(SensorySection.aroma), {extra: TasteReaction.liked});
    await tap(tester, 'notice:aroma:$extra');
    expect(flow.reactions(SensorySection.aroma), {
      extra: TasteReaction.disliked,
    });
    await tap(tester, 'sensory-next');
    expect(flow.current.section, SensorySection.taste);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aroma search says so when no aroma has the name', (
    tester,
  ) async {
    final flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    flow.next();
    await pump(tester, flow);
    final search = await openAromaSearch(tester);
    await tester.enterText(search, 'zzzz-no-such-aroma');
    await tester.pumpAndSettle();
    expect(find.text('일치하는 향을 찾지 못했어요.\n다른 단어로 검색해 보세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('aroma-search-results')), findsNothing);
    expect(flow.selected(SensorySection.aroma), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an aroma found by search joins however many the menu gave', (
    tester,
  ) async {
    final flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    flow.next();
    await pump(tester, flow);
    expect(find.text('잔에서 어떤 향이 느껴졌나요?'), findsOneWidget);
    final picked = menu.keys.take(6).toList();
    for (final key in picked) {
      await tap(tester, 'notice:aroma:$key');
    }
    final search = await openAromaSearch(tester);
    await tester.enterText(search, extra);
    await tester.pumpAndSettle();
    await tap(tester, 'search:aroma:$extra');
    expect(flow.selected(SensorySection.aroma), {...picked, extra});
    expect(flow.reactions(SensorySection.aroma)[extra], TasteReaction.liked);
    await tap(tester, 'aroma-search:done');
    // A liked chip needs two more taps to clear: burden, then off.
    await tap(tester, 'notice:aroma:${picked.first}');
    await tap(tester, 'notice:aroma:${picked.first}');
    expect(flow.selected(SensorySection.aroma), {...picked.skip(1), extra});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'both taste sides receive reasons and mouthfeel goes straight to finish',
    (tester) async {
      final flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
      flow.next();
      var completed = false;
      await pump(tester, flow, complete: () => completed = true);
      await tap(tester, 'aroma:unsure');
      expect(find.text('입안에서 느껴진 맛과 질감은 어땠나요?'), findsOneWidget);
      for (final key in ['sweetness', 'acidity']) {
        await tap(tester, 'reaction:taste:$key:liked');
      }
      await tap(tester, 'reaction:taste:bitterness:disliked');
      await tap(tester, 'reason:taste:acidity:pronounced');
      await tap(tester, 'reason:taste:acidity:harmony');
      await tap(tester, 'reason:taste:bitterness:too_strong');
      await tap(tester, 'sensory-next');
      expect(find.text('입안에서 느껴진 맛과 질감은 어땠나요?'), findsOneWidget);
      // 좋았어요 on a two-ended axis opens the chips and waits for the end.
      await tap(tester, 'judge:mouthfeel:smooth:liked');
      expect(flow.canContinue, isFalse);
      await tap(tester, 'reaction:mouthfeel:smooth:liked');
      expect(flow.canContinue, isTrue);
      // The other judgement replaces the answer, chips and all.
      await tap(tester, 'judge:mouthfeel:smooth:disliked');
      expect(
        find.byKey(const ValueKey('reaction:mouthfeel:smooth:liked')),
        findsNothing,
      );
      await tap(tester, 'reaction:mouthfeel:drying:disliked');
      await tap(tester, 'judge:mouthfeel:light:liked');
      await tap(tester, 'reaction:mouthfeel:heavy:liked');
      // A single sensation stores at once.
      await tap(tester, 'reaction:mouthfeel:bubbles:liked');
      await tap(tester, 'reaction:mouthfeel:warmth:disliked');
      expect(flow.selected(SensorySection.mouthfeel), {
        'drying',
        'heavy',
        'bubbles',
        'warmth',
      });
      await tap(tester, 'sensory-next');
      expect(flow.current.page, SensoryPage.finish);
      expect(flow.reasons(SensorySection.taste, 'acidity'), {'harmony'});
      expect(flow.reasons(SensorySection.taste, 'sweetness'), isEmpty);
      expect(flow.reasons(SensorySection.taste, 'bitterness'), {'too_strong'});
      await tap(tester, 'sensory-next');
      expect(completed, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finish groups show every option in axis order without collecting feedback',
    (tester) async {
      final flow = registry.createFlow()..setRevisit(RevisitIntent.unsure);
      for (final key in flow.askedTasteKeys) {
        flow.toggleReaction(SensorySection.taste, key, TasteReaction.liked);
      }
      while (flow.current.page != SensoryPage.finish) {
        flow.next();
      }
      await pump(tester, flow);
      // No expand step: the whole bank is on the page.
      const extra = FinishOption.offFlavor;
      expect(find.byKey(const ValueKey('finish:expand')), findsNothing);
      const groups = {
        'liked': [
          FinishOption.pleasantLength,
          FinishOption.clean,
          FinishOption.aromaEcho,
        ],
        'disliked': [
          FinishOption.tooShort,
          FinishOption.heavy,
          FinishOption.offFlavor,
        ],
      };
      expect(find.text('좋았던 마무리'), findsOneWidget);
      expect(find.text('아쉬웠던 마무리'), findsOneWidget);
      double? previousGroupTop;
      for (final group in groups.entries) {
        final section = find.byKey(ValueKey('finish-group:${group.key}'));
        final top = tester.getTopLeft(section).dy;
        if (previousGroupTop != null) {
          expect(top, greaterThan(previousGroupTop));
        }
        previousGroupTop = top;
        double? previousOptionTop;
        for (final value in group.value) {
          final option = find.byKey(ValueKey('finish:${value.name}'));
          expect(option, findsOneWidget);
          expect(
            find.descendant(of: section, matching: option),
            findsOneWidget,
          );
          // Two chips share a row, so axis order reads left to right, then
          // down: a later option never sits above an earlier one.
          final optionTop = tester.getTopLeft(option).dy;
          if (previousOptionTop != null) {
            expect(optionTop, greaterThanOrEqualTo(previousOptionTop));
          }
          previousOptionTop = optionTop;
        }
        expect(
          find.descendant(
            of: section,
            matching: find.byKey(const ValueKey('finish:unsure')),
          ),
          findsNothing,
        );
      }
      await tap(tester, 'finish:${extra.name}');
      expect(flow.finish.selected, {extra});
      await tap(tester, 'finish:unsure');
      expect(flow.finish.selected, isEmpty);
      final meanings = registry.readAnswers(flow);
      // The tastes keep their answers; nothing else leaks in.
      expect(meanings.any((meaning) => meaning.subject == 'cherry'), false);
      expect(
        meanings.any(
          (meaning) =>
              meaning.subject == 'sweetness' &&
              meaning.reaction != TasteReaction.liked,
        ),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
