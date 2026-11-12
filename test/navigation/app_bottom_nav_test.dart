import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/widgets/app_bottom_nav.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';

void main() {
  Widget bar(AppTab active, ValueChanged<AppTab> onTab) => MaterialApp(
    home: Scaffold(
      bottomNavigationBar: AppBottomNav(
        activeTab: active,
        onTab: onTab,
        onRecord: (_) {},
      ),
    ),
  );

  double scaleOf(WidgetTester tester, String label) {
    final slot = find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    );
    return tester
        .widget<ScaleTransition>(
          find.descendant(of: slot, matching: find.byType(ScaleTransition)),
        )
        .scale
        .value;
  }

  testWidgets('tapping a tab reports it and pops its icon once it lights up', (
    tester,
  ) async {
    AppTab? tapped;
    await tester.pumpWidget(bar(AppTab.home, (tab) => tapped = tab));
    await tester.tap(find.text('취향'));
    expect(tapped, AppTab.preference);

    await tester.pumpWidget(bar(AppTab.preference, (_) {}));
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester, '취향'), lessThan(1));
    await tester.pumpAndSettle();
    expect(scaleOf(tester, '취향'), 1);
    expect(scaleOf(tester, '홈'), 1);
  });

  testWidgets(
    '기록 is drawn black, apart from the burgundy of the tab you are on',
    (tester) async {
      await tester.pumpWidget(bar(AppTab.home, (_) {}));
      await tester.pumpAndSettle();
      Color? iconColor(String label) => tester
          .widget<AppIcon>(
            find.descendant(
              of: find.ancestor(
                of: find.text(label),
                matching: find.byType(InkWell),
              ),
              matching: find.byType(AppIcon),
            ),
          )
          .color;
      expect(iconColor('기록'), AppColors.textPrimary);
      expect(iconColor('홈'), AppColors.actionPrimary);
    },
  );
}
