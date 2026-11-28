import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import '../support/app_test_harness.dart';

void main() {
  testWidgets('my page keeps its content out from under the status bar once '
      'it scrolls; at rest the picture reaches the top', (tester) async {
    // A phone short enough for the page to scroll.
    await pumpAppAtRoute(tester, AppRoute.profile, const Size(390, 520));
    tester.view.padding = const FakeViewPadding(top: 47);
    tester.view.viewPadding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpAndSettle();

    final cover = find.byKey(
      const ValueKey<String>('profile-status-bar-cover'),
    );
    double shown() => tester
        .widget<Opacity>(
          find.ancestor(of: cover, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(tester.getSize(cover).height, 47);
    expect(shown(), 0);

    await tester.drag(
      find
          .descendant(
            of: find.byType(ProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(shown(), 1);
  });
}
