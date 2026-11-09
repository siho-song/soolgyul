import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';
import 'package:soolgyul/src/widgets/app_term_tooltip.dart';
import '../support/design_taste_card.dart';

void main() {
  testWidgets('opening a saved card does not read as making one', (
    tester,
  ) async {
    Future<void> pump(bool savedCard) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TasteCardStatusScreen(
          state: TasteCardLoadState.loading,
          savedCard: savedCard,
        ),
      ),
    );
    await pump(false);
    expect(find.text('술결을 정리하고 있어요'), findsOneWidget);
    await pump(true);
    expect(find.text('술결카드를 불러오고 있어요'), findsOneWidget);
    expect(find.text('술결을 정리하고 있어요'), findsNothing);
  });

  testWidgets(
    'the card shows the product, 술결 한입 and the two reason sections in order',
    (tester) async {
      final viewData = _viewData();
      await _pumpTasteCard(
        tester,
        viewData: viewData,
        onSave: () {},
        viewportSize: const Size(402, 5200),
      );

      final bite = find.byKey(const ValueKey<String>('taste-card-bite'));
      final bridge = find.byKey(const ValueKey<String>('taste-card-bridge'));
      final positive = find.byKey(
        const ValueKey<String>('taste-card-positive'),
      );
      final burden = find.byKey(const ValueKey<String>('taste-card-burden'));
      // The reasons start folded under the bridge.
      expect(find.text('자세히 보기'), findsOneWidget);
      expect(positive, findsNothing);
      expect(burden, findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('taste-card-toggle')));
      await tester.pumpAndSettle();
      for (final section in <Finder>[bite, bridge, positive, burden]) {
        expect(section, findsOneWidget);
      }
      expect(
        tester.getTopLeft(bite).dy,
        lessThan(tester.getTopLeft(bridge).dy),
      );
      expect(
        tester.getTopLeft(bridge).dy,
        lessThan(tester.getTopLeft(positive).dy),
      );
      expect(
        tester.getTopLeft(positive).dy,
        lessThan(tester.getTopLeft(burden).dy),
      );

      for (final text in <String>[
        viewData.bite.nickname,
        ...viewData.bite.tags.map((tag) => '#${tag.label}'),
        // Marked words (**산미**) are drawn as bold spans; the finder sees plain text.
        viewData.bite.summary.replaceAll('**', ''),
        '다음 술은 이렇게 골라보세요!',
        '바르베라',
        '왜 잘 맞았을까요?',
        '왜 부담이었을까요?',
        '01',
        '02',
        viewData.positive.first.answer,
        viewData.burden.single.text.replaceAll('**', ''),
        '조금 더 자세히 알아볼까요?',
        '접기',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      for (final text in <String>[
        '술결 한입',
        '한눈에 보기 좋게, 민지님의 이번 술결에서 핵심만 정리했어요.',
        '핵심 요약',
        '술결 딥다이브',
        '이번 발견',
        '취향 공식',
        '다음 선택',
        '술결 맞춤픽',
        '다음에 살펴볼 점',
        '다른 매력도 즐겨볼까요?',
      ]) {
        expect(find.text(text), findsNothing, reason: text);
      }
      expect(
        find.byKey(const ValueKey<String>('save-preference-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey<String>('taste-card-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('자세히 보기'), findsOneWidget);
      expect(positive, findsNothing);
      expect(burden, findsNothing);
      expect(
        find.byKey(const ValueKey<String>('save-preference-button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('a section with nothing to say is left out, heading and all', (
    tester,
  ) async {
    await _pumpTasteCard(
      tester,
      viewData: _viewData(positive: const <TasteCardParagraphViewData>[]),
      onSave: () {},
      viewportSize: const Size(402, 5200),
      expanded: true,
    );
    expect(find.text('왜 잘 맞았을까요?'), findsNothing);
    expect(find.text('왜 부담이었을까요?'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsNothing);

    await _pumpTasteCard(
      tester,
      viewData: _viewData(
        positive: const <TasteCardParagraphViewData>[],
        burden: const <TasteCardParagraphViewData>[],
        guide: null,
      ),
      onSave: () {},
      viewportSize: const Size(402, 5200),
    );
    expect(
      find.byKey(const ValueKey<String>('taste-card-bridge')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('taste-card-guide')),
      findsNothing,
    );
    expect(find.text('다음 술은 이렇게 골라보세요!'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('save-preference-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an explained word is dotted, opens its balloon, and the first sheet carries the hint',
    (tester) async {
      const term = TasteCardTermViewData(
        word: '산미',
        label: '산미',
        kind: '맛',
        description: '레몬이나 풋사과를 깨물었을 때처럼 침이 고이는 새콤한 맛의 강도예요',
      );
      await _pumpTasteCard(
        tester,
        viewData: _viewData(
          positive: const <TasteCardParagraphViewData>[
            TasteCardParagraphViewData(
              answer: '깔끔하게 떨어지는 산미',
              text:
                  '단맛이 거의 없어서 **산미** 특유의 산뜻함이 드러나요. 이 특징이 **기분 좋은 매력**으로 다가온 것 같아요.',
              terms: <TasteCardTermViewData>[term],
            ),
          ],
          burden: const <TasteCardParagraphViewData>[
            TasteCardParagraphViewData(
              answer: '떫은 조임',
              text: '**떫은 조임**이 혀를 붙들어요.',
            ),
          ],
        ),
        onSave: () {},
        viewportSize: const Size(402, 5200),
        expanded: true,
      );
      // No line tells the reader about dotted words; the dots say it.
      expect(find.text('점선 친 말을 누르면 뜻을 볼 수 있어요'), findsNothing);
      // The explained word is its own dotted span; the verdict stays plain bold.
      final word = find.byKey(const ValueKey<String>('taste-card-term-산미'));
      expect(word, findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(of: word, matching: find.byType(Text)),
            )
            .style
            ?.decorationStyle,
        TextDecorationStyle.dotted,
      );
      expect(
        find.byKey(const ValueKey<String>('taste-card-term-기분 좋은 매력')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('taste-card-term-떫은 조임')),
        findsNothing,
      );

      await tester.tap(word);
      await tester.pumpAndSettle();
      expect(find.byType(TermTooltipLayer), findsOneWidget);
      expect(find.text(term.description), findsOneWidget);
      expect(
        tester.getRect(find.text(term.description)).bottom,
        lessThan(tester.getRect(word).top),
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(TermTooltipLayer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a tag the dictionary explains is dotted and opens the same balloon',
    (tester) async {
      await _pumpTasteCard(
        tester,
        viewData: _viewData(
          tags: const <TasteCardTagViewData>[
            TasteCardTagViewData(
              label: '복숭아향',
              kind: TasteCardTagKind.liked,
              term: TasteCardTermViewData(
                word: '복숭아향',
                label: '복숭아',
                kind: '향',
                description: '잘 익은 복숭아를 베어 물었을 때 퍼지는 달콤하고 보드라운 과즙 향이에요',
              ),
            ),
            TasteCardTagViewData(label: '떫은맛', kind: TasteCardTagKind.less),
          ],
        ),
        onSave: () {},
        viewportSize: const Size(402, 5200),
      );
      final explained = find.byKey(
        const ValueKey<String>('taste-card-tag-term-복숭아향'),
      );
      expect(explained, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('taste-card-tag-term-떫은맛')),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: explained, matching: find.text('#복숭아향')),
            )
            .style
            ?.decorationStyle,
        TextDecorationStyle.dotted,
      );
      expect(tester.widget<Text>(find.text('#떫은맛')).style?.decoration, isNull);
      await tester.tap(explained);
      await tester.pumpAndSettle();
      expect(find.byType(TermTooltipLayer), findsOneWidget);
      expect(find.textContaining('복숭아  향'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('term-tooltip-close')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TermTooltipLayer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the balanced card shows 왜 편안했을까요 as its only section', (
    tester,
  ) async {
    await _pumpTasteCard(
      tester,
      viewData: _viewData(
        positive: const <TasteCardParagraphViewData>[],
        burden: const <TasteCardParagraphViewData>[],
        balanced: const <TasteCardParagraphViewData>[
          TasteCardParagraphViewData(
            answer: '산미가 튀지 않고 적당했어요',
            text: '사실 테스트 리슬링은 일반 와인보다 산미가 꽤 높은 편(산도 4)에 속해요.',
          ),
        ],
      ),
      onSave: () {},
      viewportSize: const Size(402, 5200),
      expanded: true,
    );
    expect(
      find.byKey(const ValueKey<String>('taste-card-balanced')),
      findsOneWidget,
    );
    expect(find.text('왜 편안했을까요?'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('왜 잘 맞았을까요?'), findsNothing);
    expect(find.text('왜 부담이었을까요?'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('taste-card-bridge')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved result exposes its saved state in the primary action', (
    tester,
  ) async {
    await _pumpTasteCard(tester, onSave: () {}, isSaved: true);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('save-preference-button')),
      420,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('저장 완료'), findsOneWidget);
  });

  testWidgets('on the web a bar fixed at the bottom opens the app instead of '
      'the save button', (tester) async {
    var opened = 0;
    await _pumpTasteCard(tester, onSave: () {}, onOpenApp: () => opened++);
    final openApp = find.byKey(const ValueKey<String>('open-app-button'));
    expect(openApp, findsOneWidget);
    expect(find.text('앱에서 내 술결 확인하기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('save-preference-button')),
      findsNothing,
    );
    // Visible at once, and still there once the card is scrolled.
    final before = tester.getTopLeft(openApp);
    expect(before.dy, lessThan(874));
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(openApp), before);
    await tester.tap(openApp);
    expect(opened, 1);
  });

  testWidgets(
    'a newly loaded snapshot starts folded even after the prior card was opened',
    (tester) async {
      await _pumpTasteCard(
        tester,
        viewData: _viewData(snapshotRef: 'snapshot-first'),
        onSave: () {},
        expanded: true,
      );
      expect(find.text('접기'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('taste-card-positive')),
        findsOneWidget,
      );

      await _pumpTasteCard(
        tester,
        viewData: _viewData(snapshotRef: 'snapshot-second'),
        onSave: () {},
      );

      expect(find.text('자세히 보기'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('taste-card-positive')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpTasteCard(
  WidgetTester tester, {
  required VoidCallback onSave,
  TasteCardSnapshotViewData? viewData,
  bool isSaved = false,
  VoidCallback? onOpenApp,
  Size viewportSize = const Size(402, 874),
  bool expanded = false,
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: TasteCardScreen(
          viewData: viewData ?? designTasteCard,
          onSave: onSave,
          isSaved: isSaved,
          onOpenApp: onOpenApp,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (expanded) {
    await tester.tap(find.byKey(const ValueKey<String>('taste-card-toggle')));
    await tester.pumpAndSettle();
  }
}

TasteCardSnapshotViewData _viewData({
  String snapshotRef = 'snapshot-widget',
  String drinkName = '테스트 리슬링',
  String? categoryLabel = '와인',
  List<TasteCardParagraphViewData>? positive,
  List<TasteCardParagraphViewData>? burden,
  List<TasteCardParagraphViewData> balanced =
      const <TasteCardParagraphViewData>[],
  List<TasteCardTagViewData> tags = const <TasteCardTagViewData>[
    TasteCardTagViewData(label: '복숭아향', kind: TasteCardTagKind.liked),
    TasteCardTagViewData(label: '산미', kind: TasteCardTagKind.liked),
    TasteCardTagViewData(label: '떫은맛', kind: TasteCardTagKind.less),
  ],
  TasteCardGuideViewData? guide = const TasteCardGuideViewData(
    head: '떫은맛만 줄인 레드 와인으로 가보세요.',
    picks: <TasteCardGuidePickViewData>[
      TasteCardGuidePickViewData(
        country: 'it',
        place: '이탈리아 피에몬테',
        keyword: '바르베라',
      ),
    ],
  ),
}) {
  return TasteCardSnapshotViewData(
    product: TasteCardProductViewData(
      drinkNameSnapshot: drinkName,
      userName: '민지',
      categoryLabel: categoryLabel,
    ),
    bite: TasteCardBiteViewData(
      nickname: '선명한 프루티 러버',
      tags: tags,
      summary:
          '싱그러운 **복숭아 향**과 침샘을 자극하는 깔끔한 **산미**는 반갑지만, '
          '입안을 꽉 조이는 **떫은맛**은 아직 조금 버거워요.',
      guide: guide,
    ),
    positive:
        positive ??
        const <TasteCardParagraphViewData>[
          TasteCardParagraphViewData(
            answer: '또렷한 과일 향과 깔끔하게 떨어지는 산미',
            text:
                '이 와인은 향이 짙어서 여러 풍미가 섞여 있어도 **복숭아 향**이 또렷하게 피어올라요. '
                '또한 단맛이 거의 없어서 **산미** 특유의 산뜻함이 그대로 드러나요. '
                '이 두 가지 특징이 입안에서 **기분 좋은 매력**으로 다가온 것 같아요.',
          ),
        ],
    burden:
        burden ??
        const <TasteCardParagraphViewData>[
          TasteCardParagraphViewData(
            answer: '떫은 조임',
            text:
                '이 와인은 타닌이 많아서 **떫은 조임**이 혀와 입안을 붙들며 본래의 매끄러운 촉감을 가려 버려요. '
                '이 특징이 **부담**으로 다가온 것 같아요.',
          ),
        ],
    balanced: balanced,
    snapshotRef: snapshotRef,
  );
}
