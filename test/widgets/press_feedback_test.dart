import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_press_scale.dart';
import 'package:soolgyul/src/widgets/app_surface.dart';

Widget page(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

double scaleOf(WidgetTester tester, Finder within) => tester
    .widget<AnimatedScale>(
      find.descendant(of: within, matching: find.byType(AnimatedScale)),
    )
    .scale;

void main() {
  testWidgets('a card shrinks while it is pressed and comes back', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      page(
        AppSurface(
          variant: AppSurfaceVariant.card,
          onPressed: () => taps++,
          child: const SizedBox(width: 200, height: 80),
        ),
      ),
    );
    final card = find.byType(AppSurface);
    expect(scaleOf(tester, card), 1);

    final press = await tester.startGesture(tester.getCenter(card));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scaleOf(tester, card), AppPressScale.pressedScale);

    await press.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester, card), 1);
    expect(taps, 1);
  });

  testWidgets('a button shrinks while it is pressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      page(AppButton(label: '저장', onPressed: () => taps++)),
    );
    final button = find.byType(AppButton);

    final press = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scaleOf(tester, button), AppPressScale.pressedScale);
    await press.up();
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
