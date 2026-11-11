import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/core/sensory/revisit_intent.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/direct_aroma_choices.dart';
import 'package:soolgyul/src/core/sensory/finish_choices.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/core/sensory/sensory_asked_keys.dart';
import 'package:soolgyul/src/core/sensory/sensory_meanings.dart';
import 'package:soolgyul/src/core/sensory/sensory_option_definitions.dart';
import 'package:soolgyul/src/core/sensory/sensory_question_flow.dart';
import 'package:soolgyul/src/core/sensory/taste_reactions.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_layout.dart';
import 'package:soolgyul/src/features/onboarding/presentation/sensory/aroma_picker.dart';
import 'package:soolgyul/src/features/onboarding/presentation/sensory_questionnaire_screen.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';
import 'package:soolgyul/src/features/onboarding/data/dictionary_views.dart';

Map<String, dynamic> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final vocabulary = serviceVocabularyView(
    _read('catalog/dictionary/terms.json'),
  );
  final registry = SensoryMeaningRegistry(
    vocabulary: vocabulary,
    tasteBank: _read('catalog/sensory/palate-question-bank.json'),
    definitions: SensoryOptionDefinitions.fromJson(
      _read('catalog/sensory/answer-option-definitions.json'),
    ),
  );
  final engine = DirectAromaChoiceEngine(
    reference: _read('catalog/sensory/aroma-choice-reference.json'),
    vocabulary: vocabulary,
    sourceCatalog: sensoryCatalogView(_read('catalog/dictionary/terms.json')),
    alcoholTaxonomy: taxonomyView(_read('catalog/dictionary/terms.json')),
  );
  final menu = OnboardingAromaMenu.forCategory('wine');
  // An aroma the menu has no chip for, reachable only through the search.
  final extra = registry.aromaKeys.firstWhere(
    (key) => !menu.keys.contains(key),
  );

  Future<void> pump(
    WidgetTester tester,
    SensoryQuestionFlow flow, {
    VoidCallback? complete,
    bool aromaSearch = true,
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
            aromaEngine: aromaSearch ? engine : null,
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
      'chips, no check mark, five max; the first record has no search', (
    tester,
  ) async {
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
    // The tap guide and the count share the description line; the search
    // sits right under it, above the first group.
    expect(find.text(AromaTapGuide.text), findsOneWidget);
    expect(find.text('0/5'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OnboardingQuestionHeader),
        matching: find.text('0/5'),
      ),
      findsOneWidget,
    );
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

    final keys = menu.keys.take(6).toList();
    for (final key in keys) {
      final chip = find.byKey(ValueKey('notice:aroma:$key'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }
    expect(flow.selected(SensorySection.aroma), keys.take(5).toSet());
    expect(find.text('5/5'), findsOneWidget);
    expect(find.text('향은 최대 5개까지 선택할 수 있어요.'), findsOneWidget);
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

    // The first record has the menu alone, no search.
    final first = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    first.next();
    await pump(tester, first, aromaSearch: false);
    expect(find.byKey(const ValueKey('aroma-search:open')), findsNothing);
    expect(find.text(menu.groups.first.title), findsOneWidget);
    expect(find.text('0/5'), findsOneWidget);
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
        await tap(tester, 'reaction:taste:$other:fine');
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
      // 적당했어요 has no reasons.
      await tap(tester, 'reaction:taste:$subject:fine');
      expect(
        find.byKey(ValueKey('reason:taste:$subject:too_strong')),
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
    await tap(tester, 'reaction:taste:sweetness:fine');
    await tap(tester, 'reaction:taste:acidity:fine');
    await tap(tester, 'sensory-next');
    // A white wine is asked weight and warmth only, on one page.
    expect(find.text('무게감'), findsOne);
    expect(find.text('열감'), findsOne);
    expect(
      find.byKey(const ValueKey('reaction:mouthfeel:heavy:fine')),
      findsOne,
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
    await tap(tester, 'notice:aroma:cherry'); // liked
    await tap(tester, 'notice:aroma:cherry'); // a second tap: a burden
    expect(flow.reactions(SensorySection.aroma), {
      'cherry': TasteReaction.disliked,
    });
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
    expect(find.text('1/5'), findsWidgets);
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

  testWidgets('the menu and the search share the five limit', (tester) async {
    final flow = registry.createFlow()..setRevisit(RevisitIntent.wantAgain);
    flow.next();
    await pump(tester, flow);
    expect(find.text('기억에 남거나 아쉬웠던 향이 있나요?'), findsOneWidget);
    for (final key in menu.keys.take(5)) {
      await tap(tester, 'notice:aroma:$key');
    }
    final search = await openAromaSearch(tester);
    await tester.enterText(search, extra);
    await tester.pumpAndSettle();
    await tap(tester, 'search:aroma:$extra');
    expect(flow.selected(SensorySection.aroma).length, 5);
    expect(flow.selected(SensorySection.aroma), isNot(contains(extra)));
    expect(find.text('향은 최대 5개까지 선택할 수 있어요.'), findsOneWidget);
    await tap(tester, 'aroma-search:done');
    expect(find.text('향은 최대 5개까지 선택할 수 있어요.'), findsNothing);
    // A liked chip needs two more taps to clear: burden, then off.
    await tap(tester, 'notice:aroma:${menu.keys.first}');
    await tap(tester, 'notice:aroma:${menu.keys.first}');
    expect(flow.selected(SensorySection.aroma).length, 4);
    await tester.enterText(await openAromaSearch(tester), extra);
    await tester.pumpAndSettle();
    await tap(tester, 'search:aroma:$extra');
    expect(flow.selected(SensorySection.aroma), contains(extra));
    expect(flow.reactions(SensorySection.aroma)[extra], TasteReaction.liked);
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
      expect(find.text('입안 가득 느껴진 맛은 어땠나요?'), findsOneWidget);
      for (final key in ['sweetness', 'acidity']) {
        await tap(tester, 'reaction:taste:$key:liked');
      }
      await tap(tester, 'reaction:taste:bitterness:disliked');
      await tap(tester, 'reason:taste:acidity:pronounced');
      await tap(tester, 'reason:taste:acidity:harmony');
      await tap(tester, 'reason:taste:bitterness:too_strong');
      await tap(tester, 'sensory-next');
      expect(find.text('마실 때 입안의 감촉은 어땠나요?'), findsOneWidget);
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
      // 적당했어요 and a single sensation store at once.
      await tap(tester, 'reaction:mouthfeel:bubbles:fine');
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
        flow.toggleReaction(SensorySection.taste, key, TasteReaction.fine);
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
      // The tastes keep their 적당했어요 answers; nothing else leaks in.
      expect(meanings.any((meaning) => meaning.subject == 'cherry'), false);
      expect(
        meanings.any(
          (meaning) =>
              meaning.subject == 'sweetness' &&
              meaning.meaning != AnswerMeaning.balanced,
        ),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
