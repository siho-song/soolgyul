import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/widgets/app_page_scroll_view.dart';

void main() {
  testWidgets('a page shorter than the screen can be pulled to refresh', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPageScrollView(
            onRefresh: () async => refreshes += 1,
            child: const SizedBox(height: 120, child: Text('짧은 화면')),
          ),
        ),
      ),
    );

    await tester.fling(find.text('짧은 화면'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(refreshes, 1);
  });

  testWidgets('without a refresh the page has no pull gesture', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppPageScrollView(child: SizedBox(height: 120))),
      ),
    );

    expect(find.byType(RefreshIndicator), findsNothing);
  });
}
