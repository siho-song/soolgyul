import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/answered_after_return.dart';

void main() {
  Future<void> leaveAndReturn(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('a member back from the other app without an answer is not '
      'left waiting', (tester) async {
    final neverAnswered = Completer<String>();
    Object? ended;
    unawaited(
      answeredOrGivenUpAfterReturn(
        neverAnswered.future,
        giveUp: () => StateError('gave up'),
      ).then<void>((_) {}, onError: (Object error) => ended = error),
    );

    // Away in the other app, however long: still waiting.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(minutes: 2));
    expect(ended, isNull);

    await leaveAndReturn(tester);
    await tester.pump(const Duration(seconds: 19));
    expect(ended, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(ended, isA<StateError>());

    // An answer after that is dropped, not thrown anywhere.
    neverAnswered.complete('late');
    await tester.pump();
  });

  testWidgets('an answer that arrives after giving up is handed over, when '
      'somebody asked for it', (tester) async {
    final slow = Completer<String>();
    Object? ended;
    final late = <String>[];
    unawaited(
      answeredOrGivenUpAfterReturn(
        slow.future,
        giveUp: () => StateError('gave up'),
        wait: const Duration(seconds: 3),
        onLate: late.add,
      ).then<void>((_) {}, onError: (Object error) => ended = error),
    );

    await leaveAndReturn(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(ended, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(ended, isA<StateError>());
    expect(late, isEmpty);

    slow.complete('token');
    await tester.pump();
    expect(late, <String>['token']);
  });

  testWidgets('an answer in time is the result, and not handed over as '
      'late', (tester) async {
    final answer = Completer<String>();
    String? result;
    final late = <String>[];
    unawaited(
      answeredOrGivenUpAfterReturn(
        answer.future,
        giveUp: () => StateError('gave up'),
        wait: const Duration(seconds: 3),
        onLate: late.add,
      ).then((value) => result = value),
    );

    await leaveAndReturn(tester);
    await tester.pump(const Duration(seconds: 1));
    answer.complete('token');
    await tester.pump();
    expect(result, 'token');
    expect(late, isEmpty);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('an answer that follows the return is the result', (
    tester,
  ) async {
    final answer = Completer<String>();
    String? result;
    unawaited(
      answeredOrGivenUpAfterReturn(
        answer.future,
        giveUp: () => StateError('gave up'),
      ).then((value) => result = value),
    );

    await leaveAndReturn(tester);
    await tester.pump(const Duration(seconds: 3));
    answer.complete('token');
    await tester.pump();
    expect(result, 'token');
    // No clock is left running.
    await tester.pump(const Duration(seconds: 30));
  });
}
