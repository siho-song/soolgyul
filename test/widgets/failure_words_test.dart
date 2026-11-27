import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/widgets/app_state_view.dart';

// The shared failed-view parts are handed the error a screen caught: a
// connection failure is told in the connection's one wording, any other
// failure in the screen's own.

void main() {
  final offline = ConnectionFailure(TimeoutException('no answer'));
  final fault = StateError('bad row');
  const title = '네트워크 연결이 불안정해요';
  const description = '연결을 확인한 뒤 다시 시도해 주세요.';
  const line = '$title. $description';

  test('a notice is the connection\'s line for a connection failure and the '
      'screen\'s own otherwise', () {
    expect(ConnectionFailureWords.title, title);
    expect(ConnectionFailureWords.description, description);
    expect(failureLine(offline, '저장하지 못했어요.'), line);
    expect(failureLine(fault, '저장하지 못했어요.'), '저장하지 못했어요.');
    expect(failureLine(null, '저장하지 못했어요.'), '저장하지 못했어요.');
  });

  test('a page or a popup is the connection\'s title and line for a '
      'connection failure and the screen\'s own otherwise', () {
    expect(failureWords(offline, title: '고친 답을 반영하지 못했어요.'), (
      title: title,
      description: description,
    ));
    expect(failureWords(fault, title: '고친 답을 반영하지 못했어요.'), (
      title: '고친 답을 반영하지 못했어요.',
      description: null,
    ));
    expect(
      failureWords(null, title: '앱을 시작하지 못했어요', description: '다시 시도해 주세요.'),
      (title: '앱을 시작하지 못했어요', description: '다시 시도해 주세요.'),
    );
  });

  testWidgets('a failed page and a failed card choose the wording by the '
      'error they are given, and keep the retry', (tester) async {
    var retries = 0;
    Future<void> pump(Object? error) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: <Widget>[
              AppErrorView(
                title: '기록을 불러오지 못했어요',
                error: error,
                onRetry: () => retries++,
              ),
              AppCardError(
                message: '가이드를 불러오지 못했어요.',
                error: error,
                onRetry: () => retries++,
              ),
            ],
          ),
        ),
      ),
    );

    await pump(offline);
    expect(find.text(title), findsOneWidget);
    expect(find.text(description), findsOneWidget);
    expect(find.textContaining(title), findsNWidgets(2));
    expect(find.text('기록을 불러오지 못했어요'), findsNothing);
    expect(find.text('가이드를 불러오지 못했어요.'), findsNothing);
    await tester.tap(find.text('다시 시도').first);
    await tester.tap(find.text('다시 시도').last);
    expect(retries, 2);

    for (final error in <Object?>[fault, null]) {
      await pump(error);
      expect(find.text('기록을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('가이드를 불러오지 못했어요.'), findsOneWidget);
      expect(find.textContaining(title), findsNothing);
    }
  });

  testWidgets('a loading view may say what it loads under its spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: AppLoadingView(message: '질문을 불러오고 있어요')),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('질문을 불러오고 있어요')).dy,
      greaterThan(
        tester.getBottomLeft(find.byType(CircularProgressIndicator)).dy,
      ),
    );
  });
}
