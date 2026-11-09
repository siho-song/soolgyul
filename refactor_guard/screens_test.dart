// Temporary: refactor guard. Deleted with refactor_guard/ when the refactor ends.
//
// Draws every screen of the app on its placeholder data at two phone sizes,
// top to bottom, so a refactor can prove it changed no pixel.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import '../test/support/app_test_harness.dart';
import 'snap.dart';

Future<void> pumpRoute(WidgetTester tester, AppRoute route, Size size) async {
  useViewport(tester, size);
  const channel = MethodChannel('soolgyul/debug-screen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => route.debugScreen);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  await tester.pumpWidget(
    const App(sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final route in AppRoute.values) {
    if (route == AppRoute.designLab) continue;
    for (final MapEntry(key: device, value: size) in guardViewports.entries) {
      testWidgets('route.${route.name}.$device', (tester) async {
        await pumpRoute(tester, route, size);
        await snapScrolled(tester, 'route.${route.name}.$device');
      });
    }
  }
}
