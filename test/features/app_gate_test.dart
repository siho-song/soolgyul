import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/app_gate/data/app_gate.dart';
import 'package:soolgyul/src/features/app_gate/presentation/app_gate_view.dart';

const _app = Directionality(
  textDirection: TextDirection.ltr,
  child: Text('the app'),
);

Future<void> _pump(
  WidgetTester tester,
  Future<AppGate?> Function() load, {
  String? installed = '1.2.0',
  String? store = 'https://example.com/store',
}) => tester.pumpWidget(
  AppGateView(
    load: load,
    installedVersion: installed,
    storeAddress: store,
    child: _app,
  ),
);

void main() {
  test('versions compare as numbers, and one that cannot be read is never '
      'too old', () {
    expect(isOlderVersion('1.9.0', '1.10.0'), isTrue);
    expect(isOlderVersion('1.10.0', '1.9.0'), isFalse);
    expect(isOlderVersion('1.2.0', '1.2.0'), isFalse);
    expect(isOlderVersion('1.2.0+45', '1.2.1'), isTrue);
    expect(isOlderVersion('2.0.0', '1.99.99'), isFalse);
    expect(isOlderVersion('unknown', '9.0.0'), isFalse);
    expect(isOlderVersion('1.0.0', 'latest'), isFalse);
  });

  test('a pause comes before an update, and the web has no version to be '
      'too old', () {
    const both = AppGate(minimumVersion: '2.0.0', maintenanceMessage: '점검');
    expect(both.decide('1.0.0'), AppGateDecision.maintenance);
    const update = AppGate(minimumVersion: '2.0.0');
    expect(update.decide('1.0.0'), AppGateDecision.updateRequired);
    expect(update.decide('2.0.0'), AppGateDecision.open);
    expect(update.decide(null), AppGateDecision.open);
    expect(
      AppGate.fromRow(const {
        'minimum_version': '1.0.0',
        'maintenance_message': '  ',
      }).decide('1.0.0'),
      AppGateDecision.open,
    );
  });

  testWidgets('the app shows while the gate is asked, and stays when the '
      'answer cannot be had', (tester) async {
    final answer = Completer<AppGate?>();
    await _pump(tester, () => answer.future);
    expect(find.text('the app'), findsOneWidget);

    answer.completeError(TimeoutException('offline'));
    await tester.pump();
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('a version below the minimum is asked to update and cannot '
      'go on', (tester) async {
    await _pump(tester, () async => const AppGate(minimumVersion: '1.3.0'));
    await tester.pumpAndSettle();

    expect(find.text('the app'), findsNothing);
    expect(find.text('업데이트가 필요해요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('app-gate-open-store')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('app-gate-ask-again')),
      findsNothing,
    );
  });

  testWidgets('without a store address the update is still asked for, '
      'without a button that leads nowhere', (tester) async {
    await _pump(
      tester,
      () async => const AppGate(minimumVersion: '1.3.0'),
      store: null,
    );
    await tester.pumpAndSettle();
    expect(find.text('업데이트가 필요해요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('app-gate-open-store')),
      findsNothing,
    );
  });

  testWidgets('a pause shows its notice; the app is back when asking again '
      'finds it over', (tester) async {
    var gate = const AppGate(maintenanceMessage: '오후 3시까지 점검해요.');
    await _pump(tester, () async => gate);
    await tester.pumpAndSettle();
    expect(find.text('잠시 점검 중이에요'), findsOneWidget);
    expect(find.text('오후 3시까지 점검해요.'), findsOneWidget);

    gate = const AppGate();
    await tester.tap(find.byKey(const ValueKey<String>('app-gate-ask-again')));
    await tester.pumpAndSettle();
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('a pause that begins while the app is open is met the next '
      'time the app comes to the front', (tester) async {
    var gate = const AppGate();
    await _pump(tester, () async => gate);
    await tester.pumpAndSettle();
    expect(find.text('the app'), findsOneWidget);

    gate = const AppGate(maintenanceMessage: '점검 중이에요.');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('잠시 점검 중이에요'), findsOneWidget);
  });
}
