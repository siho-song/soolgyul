import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';
import 'package:soolgyul/src/widgets/app_term_tooltip.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_detail_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_level_card.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_paper_card.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:soolgyul/src/widgets/level_gauge.dart';
import 'package:soolgyul/src/widgets/paper_box.dart';

import '../support/app_test_harness.dart';

const _drink = CatalogDrink(
  id: 'croisade-sb',
  displayName: '라 크라사드 소비뇽 블랑',
  nameEn: 'La Croisade Sauvignon Blanc',
  category: DrinkCategory.whiteWine,
  styleLabel: '화이트 와인',
  abvPercent: 12,
);

const _star = TasteFitVerdict(
  productId: 'croisade-sb',
  badge: TasteFitBadge.star,
  headline: '딱 맞는 PICK !',
  tags: <String>['#상큼한_과일향', '#침고이는_산미', '#부드러운_목넘김'],
  sentence: '평소 민지님께서 좋아하신 상큼한 과일 향, 산뜻한 산미, 부드러운 목넘김을 갖고 있는 술이라 시도해 보셔도 괜찮아요.',
  levels: <String, int>{
    'sweetness': 1,
    'acidity': 5,
    'astringency': 1,
    'body': 4,
    'finish_length': 5,
  },
  facts: <TasteFitFact>[
    TasteFitFact(
      kind: 'grape',
      label: '소비뇽 블랑',
      description: '향이 또렷한 청포도 품종이에요.',
    ),
    TasteFitFact(kind: 'region', label: '랑그독'),
  ],
);

void main() {
  testWidgets('renders the verdict card, the levels and the record button', (
    tester,
  ) async {
    var recordTaps = 0;
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        selection: (
          drink: _drink,
          verdict: _star,
          hasCards: true,
          judged: true,
        ),
        onRecord: () => recordTaps += 1,
      ),
    );

    expect(find.text('라 크라사드 소비뇽 블랑'), findsOneWidget);
    expect(find.text('La Croisade Sauvignon Blanc'), findsOneWidget);
    expect(find.text('와인 · 화이트 와인'), findsOneWidget);
    expect(find.text('ALC. 12% VOL'), findsOneWidget);
    expect(find.text('딱 맞는 PICK !'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == AppIconAsset.heartFull,
      ),
      findsOneWidget,
    );
    // The headline sits by the name, not inside the paper card.
    expect(
      find.descendant(
        of: find.byType(TasteFitPaperCard),
        matching: find.text('딱 맞는 PICK !'),
      ),
      findsNothing,
    );
    for (final tag in _star.tags) {
      expect(find.text(tag), findsOneWidget);
    }
    expect(find.text(_star.sentence), findsOneWidget);
    // The verdict and the levels each sit on the shared 한지 note.
    expect(
      find.descendant(
        of: find.byType(TasteFitPaperCard),
        matching: find.byType(PaperBox),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TasteFitLevelCard),
        matching: find.byType(PaperBox),
      ),
      findsOneWidget,
    );

    // Levels are the 술결카드 gauges, one per row with the key's end words.
    final gauges = tester
        .widgetList<LevelGauge>(find.byType(LevelGauge))
        .toList(growable: false);
    expect(gauges.map((g) => g.label), <String>[
      '단맛',
      '산미',
      '탄닌(떫음)',
      '바디감',
      '피니시(여운)',
    ]);
    expect(gauges.map((g) => g.mark), <int>[1, 5, 1, 4, 5]);
    expect(gauges[0].low, '낮음');
    expect(gauges[0].high, '높음');
    expect(gauges[2].low, '약함');
    expect(gauges[3].high, '묵직함');
    expect(gauges[4].high, '긺');
    expect(find.text('탄산'), findsNothing);

    final button = find.byKey(
      const ValueKey<String>('taste-fit-record-button'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(recordTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fact chips open the dictionary explanation in a balloon', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        selection: (
          drink: _drink,
          verdict: _star,
          hasCards: true,
          judged: true,
        ),
        onRecord: () {},
      ),
    );

    expect(find.text('소비뇽 블랑'), findsOneWidget);
    expect(find.text('랑그독'), findsOneWidget);
    await tester.tap(find.text('소비뇽 블랑'));
    await tester.pumpAndSettle();

    expect(find.textContaining('소비뇽 블랑  품종'), findsOneWidget);
    expect(find.text('향이 또렷한 청포도 품종이에요.'), findsOneWidget);
    // The balloon sits by the chip and the page stays visible around it.
    expect(find.byType(TermTooltipLayer), findsOneWidget);
    expect(find.text('라 크라사드 소비뇽 블랑'), findsOneWidget);
    final balloon = tester.getRect(find.text('향이 또렷한 청포도 품종이에요.'));
    final chip = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('taste-fit-fact-grape-소비뇽 블랑')),
        matching: find.text('소비뇽 블랑'),
      ),
    );
    expect(balloon.bottom, lessThan(chip.top));

    // The tapped chip stays filled while the balloon is open.
    AppChip chipOf(String label) => tester.widget<AppChip>(
      find.descendant(
        of: find.byKey(ValueKey<String>('taste-fit-fact-grape-$label')),
        matching: find.byType(AppChip),
      ),
    );
    expect(chipOf('소비뇽 블랑').selected, isTrue);

    // Its ✕ closes it.
    await tester.tap(find.byKey(const ValueKey<String>('term-tooltip-close')));
    await tester.pumpAndSettle();
    expect(find.byType(TermTooltipLayer), findsNothing);
    expect(find.text('향이 또렷한 청포도 품종이에요.'), findsNothing);
    expect(chipOf('소비뇽 블랑').selected, isFalse);

    // So does any tap outside.
    await tester.tap(find.text('소비뇽 블랑'));
    await tester.pumpAndSettle();
    expect(find.byType(TermTooltipLayer), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(TermTooltipLayer), findsNothing);

    // Only the chip with an explanation carries the ⓘ mark (랑그독 has none).
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == AppIconAsset.info,
      ),
      findsOneWidget,
    );
  });

  testWidgets('without saved cards the hint replaces the paper card', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        selection: (
          drink: _drink,
          verdict: _star,
          hasCards: false,
          judged: true,
        ),
        onRecord: () {},
      ),
    );

    expect(find.text(tasteFitNoCardsHint), findsOneWidget);
    expect(find.byType(TasteFitPaperCard), findsNothing);
    expect(find.text('딱 맞는 PICK !'), findsNothing);
    expect(find.byType(TasteFitLevelCard), findsOneWidget);
    expect(find.text('이 술 기록하기'), findsOneWidget);
  });

  testWidgets('a caution verdict shows the empty heart and its level', (
    tester,
  ) async {
    const caution = TasteFitVerdict(
      productId: 'croisade-sb',
      badge: TasteFitBadge.caution,
      headline: '아쉬운 PICK !',
      tags: <String>['#쏘는_탄산'],
      sentence: '탄산이 강한 편이라 부담스러우실 수 있어요.',
      levels: <String, int>{'carbonation': 5},
    );
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        selection: (
          drink: _drink,
          verdict: caution,
          hasCards: true,
          judged: true,
        ),
        onRecord: () {},
      ),
    );

    expect(find.text('아쉬운 PICK !'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == AppIconAsset.heartEmpty,
      ),
      findsOneWidget,
    );
    expect(find.text('탄산'), findsOneWidget);
    expect(find.text('강함'), findsOneWidget);
  });

  testWidgets('a bottle tapped before its badge came waits for its verdict', (
    tester,
  ) async {
    final answer = Completer<TasteFitResponse>();
    final gateway = _Gateway(answer.future);
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        selection: (
          drink: _drink,
          verdict: null,
          hasCards: true,
          judged: false,
        ),
        gateway: gateway,
        onRecord: () {},
      ),
    );

    expect(gateway.asked, <List<String>>[
      <String>[_drink.id],
    ]);
    expect(
      find.byKey(const ValueKey<String>('taste-fit-judging')),
      findsOneWidget,
    );
    expect(find.byType(TasteFitPaperCard), findsNothing);

    answer.complete(
      TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{_drink.id: _star},
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('taste-fit-judging')),
      findsNothing,
    );
    expect(find.text(_star.headline), findsOneWidget);
    expect(find.byType(TasteFitPaperCard), findsOneWidget);
  });

  testWidgets('a bottle the fit call already answered asks nothing more', (
    tester,
  ) async {
    final gateway = _Gateway(Completer<TasteFitResponse>().future);
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        selection: (drink: _drink, verdict: null, hasCards: true, judged: true),
        gateway: gateway,
        onRecord: () {},
      ),
    );

    expect(gateway.asked, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('taste-fit-judging')),
      findsNothing,
    );
  });
}

class _Gateway implements TasteFitGateway {
  _Gateway(this.answer);

  final Future<TasteFitResponse> answer;
  final List<List<String>> asked = <List<String>>[];

  @override
  Future<TasteFitResponse> judge(List<String> productIds) {
    asked.add(productIds);
    return answer;
  }
}
