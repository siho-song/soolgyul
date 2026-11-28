import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/sensory/sensory_gauges.dart';
import 'package:soolgyul/src/widgets/step_scale.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';
import 'package:soolgyul/src/widgets/app_term_tooltip.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_detail_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_level_card.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_paper_card.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/widgets/taste_fit_badge.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_verdict.dart';
import 'package:soolgyul/src/widgets/level_gauge.dart';
import 'package:soolgyul/src/widgets/app_surface.dart';

import '../support/app_test_harness.dart';
import '../support/sensory_fixtures.dart';

const _drink = CatalogDrink(
  id: 'croisade-sb',
  displayName: '라 크라사드 소비뇽 블랑',
  nameEn: 'La Croisade Sauvignon Blanc',
  category: DrinkCategory.whiteWine,
  categoryKey: 'wine',
  styleKey: 'white_wine',
  styleLabel: '화이트 와인',
  abvPercent: 12,
);

/// The bundled gauge sheet, read in place: a test cannot wait on the app's
/// own bundle.
Future<SensoryGaugeDefinitions> _sheet() async => gaugeDefinitions();

const _star = TasteFitVerdict(
  productId: 'croisade-sb',
  badge: TasteFitBadge.star,
  headline: '딱 맞는 PICK',
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
  testWidgets('renders the verdict card and the levels, and no record button', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        gaugeSheet: _sheet,
        selection: (
          drink: _drink,
          verdict: _star,
          hasCards: true,
          judged: true,
        ),
      ),
    );

    expect(find.text('라 크라사드 소비뇽 블랑'), findsOneWidget);
    expect(find.text('La Croisade Sauvignon Blanc'), findsOneWidget);
    expect(find.text('와인 · 화이트 와인'), findsOneWidget);
    expect(find.text('ALC. 12% VOL'), findsOneWidget);
    expect(find.text('딱 맞는 PICK'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is TasteFitBadgeIcon && w.badge == TasteFitBadge.star,
      ),
      findsOneWidget,
    );
    // The headline sits by the name, not inside the paper card.
    expect(
      find.descendant(
        of: find.byType(TasteFitPaperCard),
        matching: find.text('딱 맞는 PICK'),
      ),
      findsNothing,
    );
    for (final tag in _star.tags) {
      expect(find.text(tag), findsOneWidget);
    }
    expect(find.text(_star.sentence), findsOneWidget);
    // The verdict and the levels each sit in the app's white box.
    expect(
      find.descendant(
        of: find.byType(TasteFitPaperCard),
        matching: find.byType(AppPanel),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TasteFitLevelCard),
        matching: find.byType(AppPanel),
      ),
      findsOneWidget,
    );

    // The levels are drawn as the 테이스팅 노트 draws a record's: the
    // gauges a white wine is asked, in the sheet's order and under its
    // names, each on the questionnaire's bar with the sheet's end words.
    final rows = tester
        .widget<StepGaugeRows>(
          find.descendant(
            of: find.byType(TasteFitLevelCard),
            matching: find.byType(StepGaugeRows),
          ),
        )
        .rows;
    expect(rows, <StepGaugeRow>[
      (label: '당도', level: 1, ends: ('드라이', '스위트')),
      (label: '산미', level: 5, ends: ('로우', '하이')),
      (label: '바디', level: 4, ends: ('라이트', '풀바디')),
      (label: '여운', level: 5, ends: ('쇼트', '롱 피니시')),
    ]);
    expect(find.byType(StepScale), findsNWidgets(4));
    // The bar's middle word under each, as on the note.
    expect(find.text('보통'), findsNWidgets(4));
    // A white wine is not asked 탄닌: the bottle's level for it is not
    // drawn. No level, no row; and none of the page's old names.
    expect(find.text('탄닌'), findsNothing);
    expect(find.text('탄산'), findsNothing);
    for (final old in ['단맛', '바디감', '피니시']) {
      expect(find.text(old), findsNothing, reason: old);
    }
    expect(find.byType(LevelGauge), findsNothing);

    // The page is read before buying; no record starts from it.
    expect(find.text('이 술 기록하기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the level card lists the gauges of the drink\'s kind for which the '
      'bottle has a level, and no level its kind is not asked', () {
    final sheet = gaugeDefinitions();
    List<(String, int)> rows(
      String? category,
      String? style,
      Map<String, int> levels,
    ) => [
      for (final row in TasteFitLevelCard(
        levels: levels,
        sheet: sheet,
        categoryKey: category,
        styleKey: style,
      ).rows)
        (row.label, row.level),
    ];
    const all = <String, int>{
      'sweetness': 1,
      'acidity': 3,
      'astringency': 4,
      'body': 4,
      'carbonation': 1,
      'finish_length': 5,
    };
    // A red wine is asked 탄닌; 탄산 is a sparkling wine's gauge.
    expect(rows('wine', 'red_wine', all), [
      ('당도', 1),
      ('산미', 3),
      ('바디', 4),
      ('탄닌', 4),
      ('여운', 5),
    ]);
    expect(rows('wine', 'sparkling_wine', all).map((row) => row.$1), [
      '당도',
      '산미',
      '바디',
      '탄산',
      '여운',
    ]);
    // A whisky's sheet names its sweetness 단맛 and has no 산미, 탄닌 or 탄산.
    expect(rows('whisky', 'single_malt_whisky', all), [
      ('단맛', 1),
      ('바디', 4),
      ('여운', 5),
    ]);
    // A 탁주's body is its 질감.
    expect(rows('korean_traditional', 'takju', {'body': 5, 'carbonation': 2}), [
      ('질감', 5),
      ('탄산', 2),
    ]);
    // A gauge the bottle has no level for is not listed, a level out of
    // range is held to the bar's five steps, and a level the app has no
    // gauge for is not drawn.
    expect(rows('wine', 'red_wine', {'body': 9, 'bitterness': 3}), [('바디', 5)]);
    expect(rows(null, null, const {}), isEmpty);
  });

  testWidgets('fact chips open the dictionary explanation in a balloon', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        gaugeSheet: _sheet,
        selection: (
          drink: _drink,
          verdict: _star,
          hasCards: true,
          judged: true,
        ),
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
        gaugeSheet: _sheet,
        selection: (
          drink: _drink,
          verdict: _star,
          hasCards: false,
          judged: true,
        ),
      ),
    );

    expect(find.text(tasteFitNoCardsHint), findsOneWidget);
    expect(find.byType(TasteFitPaperCard), findsNothing);
    expect(find.text('딱 맞는 PICK'), findsNothing);
    expect(find.byType(TasteFitLevelCard), findsOneWidget);
  });

  testWidgets('a caution verdict shows the empty heart and its level', (
    tester,
  ) async {
    const caution = TasteFitVerdict(
      productId: 'croisade-sb',
      badge: TasteFitBadge.caution,
      headline: '아쉬운 PICK',
      tags: <String>['#침고이는_산미'],
      sentence: '산미가 강한 편이라 부담스러우실 수 있어요.',
      levels: <String, int>{'acidity': 5, 'carbonation': 5},
    );
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        gaugeSheet: _sheet,
        selection: (
          drink: _drink,
          verdict: caution,
          hasCards: true,
          judged: true,
        ),
      ),
    );

    expect(find.text('아쉬운 PICK'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is TasteFitBadgeIcon && w.badge == TasteFitBadge.caution,
      ),
      findsOneWidget,
    );
    expect(find.text('산미'), findsOneWidget);
    expect(find.text('하이'), findsOneWidget);
    expect(
      tester
          .widget<StepScale>(
            find.byKey(const ValueKey<String>('taste-fit-level-산미')),
          )
          .level,
      5,
    );
    // A white wine is not asked 탄산: the bottle's level for it is not drawn.
    expect(find.text('탄산'), findsNothing);
  });

  testWidgets('a bottle tapped before its badge came waits for its verdict', (
    tester,
  ) async {
    final answer = Completer<TasteFitResponse>();
    final gateway = _Gateway(answer.future);
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        gaugeSheet: _sheet,
        selection: (
          drink: _drink,
          verdict: null,
          hasCards: true,
          judged: false,
        ),
        gateway: gateway,
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
        gaugeSheet: _sheet,
        selection: (drink: _drink, verdict: null, hasCards: true, judged: true),
        gateway: gateway,
      ),
    );

    expect(gateway.asked, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('taste-fit-judging')),
      findsNothing,
    );
  });

  testWidgets('a verdict that did not come says so and can be asked for '
      'again', (tester) async {
    final gateway = _ScriptedGateway(<Future<TasteFitResponse> Function()>[
      () async => throw const TasteFitGatewayException(),
      () async => TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{_drink.id: _star},
      ),
    ]);
    await pumpTestScreen(
      tester,
      // As 저장한 술 opens it: nothing is known of the reader's cards yet.
      TasteFitDetailScreen(
        gaugeSheet: _sheet,
        selection: (
          drink: _drink,
          verdict: null,
          hasCards: false,
          judged: false,
        ),
        gateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(tasteFitJudgeFailedMessage), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    // The first-record hint is for a reader the server said has no cards.
    expect(find.text(tasteFitNoCardsHint), findsNothing);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(gateway.asked, hasLength(2));
    expect(find.text(tasteFitJudgeFailedMessage), findsNothing);
    expect(find.text(_star.headline), findsOneWidget);
    expect(find.byType(TasteFitPaperCard), findsOneWidget);
  });

  testWidgets('a bottle not judged yet shows no first-record hint', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      TasteFitDetailScreen(
        gaugeSheet: _sheet,
        selection: (
          drink: _drink,
          verdict: null,
          hasCards: false,
          judged: false,
        ),
      ),
    );

    expect(find.text(tasteFitNoCardsHint), findsNothing);
  });

  testWidgets('a saved record asks for the verdict again', (tester) async {
    final gateway = _ScriptedGateway(<Future<TasteFitResponse> Function()>[
      () async => TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{_drink.id: _star},
      ),
    ]);
    final judged = <TasteFitVerdict?>[];
    Widget page(int revision) => TasteFitDetailScreen(
      gaugeSheet: _sheet,
      selection: (drink: _drink, verdict: null, hasCards: false, judged: true),
      gateway: gateway,
      revision: revision,
      onJudged: (verdict, _) => judged.add(verdict),
    );
    await pumpTestScreen(tester, page(0));
    expect(find.text(tasteFitNoCardsHint), findsOneWidget);
    expect(gateway.asked, isEmpty);

    // The reader recorded their first drink from here and came back.
    await pumpTestScreen(tester, page(1));
    await tester.pumpAndSettle();

    expect(gateway.asked, hasLength(1));
    expect(find.text(tasteFitNoCardsHint), findsNothing);
    expect(find.text(_star.headline), findsOneWidget);
    expect(find.byType(TasteFitPaperCard), findsOneWidget);
    expect(judged, <TasteFitVerdict?>[_star]);
  });

  testWidgets('a verdict on screen stays when asking again fails', (
    tester,
  ) async {
    final gateway = _ScriptedGateway(<Future<TasteFitResponse> Function()>[
      () async => throw const TasteFitGatewayException(),
    ]);
    Widget page(int revision) => TasteFitDetailScreen(
      gaugeSheet: _sheet,
      selection: (drink: _drink, verdict: _star, hasCards: true, judged: true),
      gateway: gateway,
      revision: revision,
    );
    await pumpTestScreen(tester, page(0));
    await pumpTestScreen(tester, page(1));
    await tester.pumpAndSettle();

    expect(gateway.asked, hasLength(1));
    expect(find.byType(TasteFitPaperCard), findsOneWidget);
    expect(find.text(tasteFitJudgeFailedMessage), findsNothing);
  });
}

/// Answers each fit call with the next of [answers].
class _ScriptedGateway implements TasteFitGateway {
  _ScriptedGateway(this.answers);

  final List<Future<TasteFitResponse> Function()> answers;
  final List<List<String>> asked = <List<String>>[];

  @override
  Future<TasteFitResponse> judge(List<String> productIds) {
    asked.add(productIds);
    return answers[asked.length - 1]();
  }
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
