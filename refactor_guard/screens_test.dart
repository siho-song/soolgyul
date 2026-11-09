// Temporary: refactor guard. Deleted with refactor_guard/ when the refactor ends.
//
// Draws every screen of the app on its placeholder data at two phone sizes,
// top to bottom, so a refactor can prove it changed no pixel.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/features/home/data/next_drink_guides.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import '../test/support/app_test_harness.dart';
import '../test/support/design_taste_card.dart';
import 'snap.dart';

/// The guide the home tab drew from the design card before a gateway was
/// required to show one.
class _DesignGuide implements NextDrinkGuidesGateway {
  @override
  Future<List<NextDrinkGuide>> load() async => <NextDrinkGuide>[
    NextDrinkGuide(
      resultId: 'design-fixture',
      kindLabel: '레드 와인',
      categoryLabel: '와인',
      guide: designTasteCard.bite.guide!,
    ),
  ];
}

Future<void> pumpRoute(WidgetTester tester, AppRoute route, Size size) async {
  useViewport(tester, size);
  const channel = MethodChannel('soolgyul/debug-screen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => route.debugScreen);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  await tester.pumpWidget(
    App(
      sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
      nextDrinkGuidesGateway: _DesignGuide(),
    ),
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
