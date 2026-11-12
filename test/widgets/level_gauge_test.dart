import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/home/data/next_drink_guides.dart';
import 'package:soolgyul/src/features/home/presentation/next_drink_guide_card.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_level_card.dart';
import 'package:soolgyul/src/widgets/app_page_scroll_view.dart';
import 'package:soolgyul/src/widgets/level_gauge.dart';

import '../support/provider_harness.dart';

class _Guides implements NextDrinkGuidesGateway {
  @override
  Future<List<NextDrinkGuide>> load() async => const <NextDrinkGuide>[
    NextDrinkGuide(
      resultId: 'result-1',
      kindLabel: '준마이 긴조',
      categoryLabel: '사케',
      guide: TasteCardGuideViewData(
        head: '머리 문장',
        levels: <TasteCardGuideLevelViewData>[
          TasteCardGuideLevelViewData(label: '당도(주도)', mark: 2, range: '2~3'),
          TasteCardGuideLevelViewData(label: '탄닌(떫음)', mark: 5, range: '5'),
          TasteCardGuideLevelViewData(label: '피니시(여운)', mark: 4, range: '3~4'),
          TasteCardGuideLevelViewData(label: '산도', mark: 3, range: '40~43%'),
        ],
      ),
    ),
  ];
}

const Map<String, int> _allLevels = <String, int>{
  'sweetness': 2,
  'acidity': 3,
  'astringency': 5,
  'body': 4,
  'carbonation': 1,
  'finish_length': 4,
};

/// Both places the gauges are drawn, on a page as wide as [width].
Future<void> _pumpGauges(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    withProviders(
      guides: _Guides(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppContentPadding(
              child: Column(
                children: <Widget>[
                  NextDrinkGuideCard(onOpenCard: (_) {}),
                  const TasteFitLevelCard(levels: _allLevels),
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
    expect(find.byType(LevelGauge), findsNWidgets(10));
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
