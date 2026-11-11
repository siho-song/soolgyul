import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';
import 'package:soolgyul/src/features/taste_card/presentation/widgets/taste_card_guide_body.dart';

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
}
