import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_start.dart';

import '../support/app_test_harness.dart';

void main() {
  testWidgets('the phone font-size setting does not enlarge the app text', (
    tester,
  ) async {
    tester.view.physicalSize = defaultAppTestViewport;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      const App(sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire),
    );
    await tester.pumpAndSettle();
    final page = tester.element(find.byType(Scaffold).first);
    expect(MediaQuery.textScalerOf(page), TextScaler.noScaling);

    // The start screen, before the app is ready, keeps it too.
    await tester.pumpWidget(
      AppStart(start: () => Future<Widget>.error(StateError('offline'))),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('다시 시도'))),
      TextScaler.noScaling,
    );
  });
}
