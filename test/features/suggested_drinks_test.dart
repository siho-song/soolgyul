import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/suggested_drinks.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';

void main() {
  test('자주 찾는 술 follows the member gender; a guest sees the men list', () {
    expect(suggestedDrinkNamesFor(ProfileGender.female), <String>[
      '칸티 모스카토 다스티 DOCG',
      '몬테스 알파 샤르도네',
      '복순도가 손막걸리',
      '조니워커 블랙 라벨',
      '닷사이 준마이 다이긴죠 45',
    ]);
    expect(suggestedDrinkNamesFor(ProfileGender.male), <String>[
      '발베니 더블우드 12년',
      '글렌피딕 15년',
      '화요 25',
      '조니워커 블랙 라벨',
      '닷사이 준마이 다이긴죠 45',
    ]);
    expect(suggestedDrinkNamesFor(null), maleSuggestedDrinkNames);
    expect(
      suggestedDrinkNamesFor(ProfileGender.other),
      maleSuggestedDrinkNames,
    );
  });
}
