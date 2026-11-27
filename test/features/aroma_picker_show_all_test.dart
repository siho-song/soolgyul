import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/core/sensory/sensory_question_flow.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/aroma_picture.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/sensory_inputs.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';

import '../support/sensory_fixtures.dart';

void main() {
  testWidgets('an answer stored as 붉은 체리, which has folded into 체리, shows '
      'the 체리 chip picked under the dictionary\'s word', (tester) async {
    tester.view.physicalSize = const Size(402, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final registry = sensoryRegistry();
    final flow = registry.createFlow(gaugesFor('wine', 'red_wine'));
    registry.restoreAnswers(flow, ['aroma:nose:red_cherry:liked']);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AromaPicker(
              selected: flow.aromas(AromaStage.nose),
              onToggle: (_) {},
              keyPrefix: 'aroma:nose:',
              menu: OnboardingAromaMenu.forDrink('wine', 'red_wine'),
              label: (key) => registry.aromaLabel(key)!,
              showAll: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cherry = tester.widget<AppChip>(
      find.byKey(const ValueKey('aroma:nose:cherry')),
    );
    expect(cherry.selected, isTrue);
    expect(cherry.label, '체리');
    expect(
      (cherry.leading! as AromaPicture).chip.picture,
      'assets/icons/aromas/cherry.webp',
    );
    expect(find.byKey(const ValueKey('aroma:nose:red_cherry')), findsNothing);
  });

  testWidgets('showAll lays out every chip of a tab, with no 더보기', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final menu = OnboardingAromaMenu.forDrink('wine', 'white_wine');
    final first = menu.groups.first;
    expect(first.chips.length, greaterThan(20));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AromaPicker(
              selected: const <String>{},
              onToggle: (_) {},
              keyPrefix: 'aroma:nose:',
              menu: menu,
              label: (key) => key,
              showAll: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final chip in first.chips) {
      expect(
        find.byKey(ValueKey('aroma:nose:${chip.key}')),
        findsOneWidget,
        reason: chip.key,
      );
    }
    expect(find.byKey(const ValueKey('aroma-more:0')), findsNothing);
    expect(find.text('더보기'), findsNothing);
  });
}
