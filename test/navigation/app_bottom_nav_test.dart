import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/widgets/app_bottom_nav.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';

void main() {
  Widget bar(AppTab active, ValueChanged<AppTab> onTab) => MaterialApp(
    home: Scaffold(
      bottomNavigationBar: AppBottomNav(activeTab: active, onTab: onTab),
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
    await tester.tap(find.text('기록'));
    expect(tapped, AppTab.preference);

    await tester.pumpWidget(bar(AppTab.preference, (_) {}));
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester, '기록'), lessThan(1));
    await tester.pumpAndSettle();
    expect(scaleOf(tester, '기록'), 1);
    expect(scaleOf(tester, '홈'), 1);
  });

  testWidgets('the bar holds four tabs: 홈, 기록, 피드, 내 정보; 기록 wears the '
      'document and lights up like any tab', (tester) async {
    final tapped = <AppTab>[];
    await tester.pumpWidget(bar(AppTab.preference, tapped.add));
    await tester.pumpAndSettle();

    final slots = find.byType(AppBottomNavItem);
    expect(slots, findsNWidgets(4));
    final labels = <String>[
      for (final slot in tester.widgetList<AppBottomNavItem>(slots)) slot.label,
    ];
    expect(labels, ['홈', '기록', '피드', '내 정보']);
    expect(find.text('취향'), findsNothing);
    // Left to right in that order, each as wide as the others.
    final centers = [
      for (final label in labels) tester.getCenter(find.text(label)).dx,
    ];
    expect(centers, [...centers]..sort());
    expect({
      for (final element in slots.evaluate())
        tester.getSize(find.byWidget(element.widget)).width,
    }, hasLength(1));

    AppIcon iconOf(String label) => tester.widget<AppIcon>(
      find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
        matching: find.byType(AppIcon),
      ),
    );
    expect(iconOf('기록').icon, AppIconAsset.navRecord);
    expect(iconOf('기록').color, AppColors.actionPrimary);
    expect(iconOf('홈').color, AppColors.textTertiary);

    for (final label in labels) {
      await tester.tap(find.text(label));
    }
    expect(tapped, AppTab.values);
  });
}
