import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_layout.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/widgets/app_bottom_nav.dart';
import 'package:soolgyul/src/widgets/app_screen.dart';

import '../support/app_test_harness.dart';

void main() {
  testWidgets('all routes render at the iPhone 17 viewport', (tester) async {
    await expectRoutesAtViewport(
      tester,
      AppRoute.values,
      AppLayout.iPhone17Viewport,
    );
  });

  testWidgets('switching bottom tabs swaps the page without a transition', (
    tester,
  ) async {
    await pumpAppAtRoute(tester, AppRoute.home);

    await tester.tap(
      find.descendant(of: find.byType(AppBottomNav), matching: find.text('취향')),
    );
    await tester.pump();

    expect(find.byType(AppScreen), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a tab is found as it was left after another was visited', (
    tester,
  ) async {
    await pumpAppAtRoute(tester, AppRoute.profile, const Size(411, 600));
    Finder tab(String label) => find.descendant(
      of: find.byType(AppBottomNav),
      matching: find.text(label),
    );
    double scrolled() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    await tester.drag(find.byType(Scrollable), const Offset(0, -200));
    await tester.pumpAndSettle();
    final left = scrolled();
    expect(left, greaterThan(0));

    await tester.tap(tab('탐색'));
    await tester.pumpAndSettle();
    expect(find.text('설정 및 지원'), findsNothing);
    await tester.tap(tab('마이페이지'));
    await tester.pumpAndSettle();

    expect(find.byType(AppScreen), findsOneWidget);
    expect(scrolled(), left);
  });

  testWidgets('web viewport keeps the mobile app width centered', (
    tester,
  ) async {
    await pumpAppAtRoute(tester, AppRoute.home, const Size(1440, 900));

    final appScreenRect = tester.getRect(find.byType(AppScreen));
    final scaffoldRect = tester.getRect(
      find.descendant(
        of: find.byType(AppScreen),
        matching: find.byType(Scaffold),
      ),
    );

    expect(appScreenRect.width, 1440);
    expect(scaffoldRect.width, AppLayout.regularPhoneWidth);
    expect(scaffoldRect.left, (1440 - AppLayout.regularPhoneWidth) / 2);
  });

  testWidgets('web users can scroll the mobile view with a mouse drag', (
    tester,
  ) async {
    await pumpAppAtRoute(tester, AppRoute.profile, const Size(1440, 700));

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);

    await tester.dragFrom(
      const Offset(720, 600),
      const Offset(0, -300),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
  });
}
