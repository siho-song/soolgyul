import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_guide_body.dart';
import 'package:soolgyul/src/widgets/text_underline.dart';

void main() {
  test('a wine guide of label words is titled 추천 라벨 표기', () {
    const grape = TasteCardGuidePickViewData(
      keyword: '바르베라',
      country: 'IT',
      place: '이탈리아 피에몬테',
    );
    const label = TasteCardGuidePickViewData(keyword: "'Saignée' 표기");
    expect(TasteCardGuideBody.picksTitle('와인', [grape]), '추천 품종 및 산지');
    expect(TasteCardGuideBody.picksTitle('와인', [label]), '라벨 추천 표기');
    expect(TasteCardGuideBody.picksTitle('와인', [grape, label]), '추천 품종 및 산지');
    expect(TasteCardGuideBody.picksTitle('위스키', [label]), '추천 캐스크 및 숙성 방식');
    expect(TasteCardGuideBody.picksTitle('사케', [label]), '라벨 추천 표기');
    expect(
      TasteCardGuideBody.picksTitle('사케', [
        const TasteCardGuidePickViewData(keyword: '준마이 긴조 · 준마이 다이긴조'),
      ]),
      '추천 등급',
    );
  });

  test('the chips get a line that says what to find on the label', () {
    const grape = TasteCardGuidePickViewData(
      keyword: '바르베라',
      country: 'IT',
      place: '이탈리아 피에몬테',
    );
    const label = TasteCardGuidePickViewData(keyword: "'Triple distilled' 표기");
    const cask = TasteCardGuidePickViewData(keyword: '셰리 캐스크(Sherry Cask)');
    const line = '병 라벨에서 이런 표기를 찾아보세요';
    expect(TasteCardGuideBody.picksDescription('위스키', [label]), line);
    expect(TasteCardGuideBody.picksDescription('위스키', [cask]), line);
    expect(TasteCardGuideBody.picksDescription('한국 전통주', [label]), line);
    expect(TasteCardGuideBody.picksDescription('와인', [label]), line);
    expect(
      TasteCardGuideBody.picksDescription('와인', [grape]),
      '병 라벨에서 이런 품종과 산지를 찾아보세요',
    );
    expect(
      TasteCardGuideBody.picksDescription('사케', [
        const TasteCardGuidePickViewData(keyword: '준마이 긴조 · 준마이 다이긴조'),
      ]),
      '병 라벨에서 이런 등급을 찾아보세요',
    );
  });

  testWidgets('a label word drops 표기 under the line that already says it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TasteCardGuideBody(
            categoryLabel: '위스키',
            guide: TasteCardGuideViewData(
              head: '머리 문장',
              picks: [
                TasteCardGuidePickViewData(
                  keyword: "'Corn Whiskey' 표기",
                  note: '옥수수의 단맛이 또렷해요.',
                ),
                TasteCardGuidePickViewData(keyword: '셰리 캐스크(Sherry Cask)'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('병 라벨에서 이런 표기를 찾아보세요'), findsOneWidget);
    expect(find.text("'Corn Whiskey'"), findsOneWidget);
    expect(find.text("'Corn Whiskey' 표기"), findsNothing);
    expect(find.text('셰리 캐스크(Sherry Cask)'), findsOneWidget);
  });

  testWidgets(
    'a cask chip underlines its name and opens its explanation; the home does not',
    (tester) async {
      const term = TasteCardTermViewData(
        word: '셰리 캐스크(Sherry Cask)',
        label: '셰리 캐스크',
        kind: '제조·숙성',
        description: '셰리 와인을 담아 두었던 오크통에서 숙성하는 방식이에요.',
      );
      const guide = TasteCardGuideViewData(
        head: '머리 문장',
        picks: [
          TasteCardGuidePickViewData(
            keyword: '셰리 캐스크(Sherry Cask)',
            note: '셰리 와인이 깊게 밴 통에서 숙성돼요. 진한 말린 과일 향이 나요.',
            term: term,
          ),
        ],
      );
      Future<void> pump({required bool explain}) => tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TasteCardGuideBody(
              categoryLabel: '위스키',
              guide: guide,
              explainPicks: explain,
            ),
          ),
        ),
      );
      const name = ValueKey<String>('taste-card-pick-term-셰리 캐스크(Sherry Cask)');

      await pump(explain: true);
      expect(
        find.descendant(
          of: find.byKey(name),
          matching: find.byType(TextUnderline),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(name));
      await tester.pumpAndSettle();
      expect(find.text(term.description), findsOneWidget);

      await pump(explain: false);
      await tester.pumpAndSettle();
      expect(find.byKey(name), findsNothing);
      expect(find.byType(TextUnderline), findsNothing);
    },
  );

  test('a served chip carries its explanation; a stored one has none', () {
    Map<String, Object?> guideWith(Map<String, Object?> pick) => {
      'head': '머리 문장',
      'picks': [pick],
      'tip': null,
      'levels': <Object?>[],
      'directions': <Object?>[],
    };
    const base = <String, Object?>{
      'country': null,
      'place': null,
      'keyword': '셰리 캐스크(Sherry Cask)',
      'note': '진한 말린 과일 향이 나요',
    };
    final served = TasteCardWireParser.parseGuide(
      guideWith({
        ...base,
        'term': {
          'word': '셰리 캐스크(Sherry Cask)',
          'label': '셰리 캐스크',
          'kind': '제조·숙성',
          'description': '셰리 와인을 담아 두었던 오크통이에요.',
        },
      }),
      'guide',
    );
    expect(served.picks.single.term?.label, '셰리 캐스크');
    final grape = TasteCardWireParser.parseGuide(
      guideWith({...base, 'term': null}),
      'guide',
    );
    expect(grape.picks.single.term, isNull);
    final stored = TasteCardWireParser.parseGuide(guideWith(base), 'guide');
    expect(stored.picks.single.term, isNull);
  });
}
