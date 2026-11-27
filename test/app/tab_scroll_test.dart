import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/widgets/app_bottom_nav.dart';

import '../support/app_test_harness.dart';

void main() {
  testWidgets('a tap on the iPhone status bar scrolls only the tab on screen '
      'to its top', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      // The status bar's height; without one no page answers its tap.
      tester.view.padding = const FakeViewPadding(top: 47);
      addTearDown(tester.view.resetPadding);
      await pumpAppAtRoute(tester, AppRoute.profile, const Size(411, 500));
      Finder tab(String label) => find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.text(label),
      );
      // The page of the tab on screen; the tabs behind are offstage.
      final page = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      double scrolled() =>
          tester.state<ScrollableState>(page.first).position.pixels;

      await tester.drag(page.first, const Offset(0, -150));
      await tester.pumpAndSettle();
      final profileLeftAt = scrolled();
      expect(profileLeftAt, greaterThan(0));

      await tester.tap(tab('홈'));
      await tester.pumpAndSettle();
      await tester.drag(page.first, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(scrolled(), greaterThan(0));

      // The tap, as the iPhone reports it to every page built.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.statusBar.name,
        SystemChannels.statusBar.codec.encodeMethodCall(
          const MethodCall('handleScrollToTop'),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(scrolled(), 0);

      // The tab behind was not on screen, so it stays where it was left.
      await tester.tap(tab('내 정보'));
      await tester.pumpAndSettle();
      expect(scrolled(), profileLeftAt);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
