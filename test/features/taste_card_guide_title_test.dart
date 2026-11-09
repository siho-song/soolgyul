import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/onboarding/presentation/taste_card_snapshot_view_data.dart';
import 'package:soolgyul/src/features/taste_card/taste_card_guide_body.dart';

void main() {
  test('a wine guide of label words is titled 추천 라벨 표기', () {
    const grape = TasteCardGuidePickViewData(
      keyword: '바르베라',
      country: 'IT',
      place: '이탈리아 피에몬테',
    );
    const label = TasteCardGuidePickViewData(keyword: "'Saignée' 표기");
    expect(TasteCardGuideBody.picksTitle('와인', [grape]), '추천 품종 & 산지');
    expect(TasteCardGuideBody.picksTitle('와인', [label]), '추천 라벨 표기');
    expect(TasteCardGuideBody.picksTitle('와인', [grape, label]), '추천 품종 & 산지');
    expect(TasteCardGuideBody.picksTitle('위스키', [label]), '추천 캐스크 & 제조 방식');
    expect(TasteCardGuideBody.picksTitle('사케', [label]), '추천 라벨 표기');
    expect(
      TasteCardGuideBody.picksTitle('사케', [
        const TasteCardGuidePickViewData(keyword: '준마이 긴조 · 준마이 다이긴조'),
      ]),
      '추천 등급',
    );
  });
}
