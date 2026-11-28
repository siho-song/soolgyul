import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/widgets/app_page_scroll_view.dart';
import 'package:soolgyul/src/widgets/level_gauge.dart';

/// Gauges inside a card's padding, on a page as wide as [width].
Future<void> _pumpGauges(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: SingleChildScrollView(
          child: AppContentPadding(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: <Widget>[
                  LevelGauge.worded(label: '당도(주도)', mark: 2, word: '드라이'),
                  LevelGauge.worded(label: '탄닌(떫음)', mark: 5, word: '탄탄한 타닌'),
                  LevelGauge.worded(label: '피니시(여운)', mark: 4, word: '긴 여운'),
                  LevelGauge.worded(label: '산도', mark: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The bars, each a box of five segments.
Iterable<double> _barWidths(WidgetTester tester) => tester
    .widgetList<SizedBox>(
      find.descendant(
        of: find.byType(LevelGauge),
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.child is Row,
        ),
      ),
    )
    .map((box) => box.width!);

void main() {
  testWidgets('the longest labels fit a 360 wide phone', (tester) async {
    await _pumpGauges(tester, 360);

    expect(tester.takeException(), isNull);
    expect(find.byType(LevelGauge), findsNWidgets(4));
    expect(_barWidths(tester), hasLength(4));
    for (final width in _barWidths(tester)) {
      expect(width, inInclusiveRange(20, 120));
    }
  });

  testWidgets('on a wide phone every bar keeps its full width', (tester) async {
    await _pumpGauges(tester, 600);

    expect(tester.takeException(), isNull);
    expect(_barWidths(tester), everyElement(120));
  });
}
