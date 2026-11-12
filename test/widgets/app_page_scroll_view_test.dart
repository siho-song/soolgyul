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

  testWidgets('a refresh ends with the page at its top, whatever the reload '
      'moved', (tester) async {
    late ScrollPosition position;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPageScrollView(
            // A reload that pushes the page down while it runs.
            onRefresh: () async {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              position.jumpTo(200);
            },
            child: Column(
              children: <Widget>[
                for (var i = 0; i < 30; i++)
                  SizedBox(height: 60, child: Text('줄 $i')),
              ],
            ),
          ),
        ),
      ),
    );
    position = tester.state<ScrollableState>(find.byType(Scrollable)).position;

    await tester.fling(find.text('줄 1'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(position.pixels, 0);
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
