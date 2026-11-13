import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_start.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/design/app_theme.dart';

import '../support/app_test_harness.dart';

void main() {
  testWidgets('a start that fails is said and reported, and trying again '
      'opens the app', (tester) async {
    final reported = <(Object, String)>[];
    addTearDown(
      captureErrorReports((error, _, where) => reported.add((error, where))),
    );
    var attempts = 0;
    await tester.pumpWidget(
      AppStart(
        start: () async {
          attempts += 1;
          if (attempts == 1) throw StateError('secure storage refused');
          return const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('the app'),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('앱을 시작하지 못했어요'), findsOneWidget);
    expect(reported.single.$2, 'start');
    expect(reported.single.$1, isA<StateError>());

    await tester.tap(find.byKey(const ValueKey<String>('app-start-retry')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('the app'), findsOneWidget);
    expect(find.text('앱을 시작하지 못했어요'), findsNothing);
  });

  testWidgets('a part of a screen that cannot be drawn is replaced by a '
      'plain sentence', (tester) async {
    await tester.pumpWidget(
      brokenView(FlutterErrorDetails(exception: StateError('build'))),
    );
    expect(find.textContaining('화면을 표시하지 못했어요'), findsOneWidget);
  });

  testWidgets('the app text keeps its own scale whatever the phone setting', (
    tester,
  ) async {
    useTestViewport(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      const App(sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire),
    );
    await tester.pumpAndSettle();
    final page = tester.element(find.byType(Scaffold).first);
    expect(
      MediaQuery.textScalerOf(page),
      const TextScaler.linear(appTextScale),
    );

    // The start screen, before the app is ready, keeps it too.
    await tester.pumpWidget(
      AppStart(start: () => Future<Widget>.error(StateError('offline'))),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('다시 시도'))),
      const TextScaler.linear(appTextScale),
    );
  });
}
