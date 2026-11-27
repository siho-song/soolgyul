import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_appearance_choices.dart';

import '../support/sensory_fixtures.dart';

void main() {
  final choices = TasteCardAppearanceChoices.fromJson(
    readJsonAsset('catalog/sensory/appearance.json'),
  );

  List<String> fields(String? category, String? style) => [
    for (final choice in choices.forDrink(category, style)) choice.field,
  ];

  test('a wine and a whisky note their colour and texture, a 탁주 its '
      'cloudiness, any other kind nothing', () {
    expect(fields('wine', 'red_wine'), ['appearance', 'appearance_texture']);
    expect(fields('whisky', null), ['appearance', 'appearance_texture']);
    expect(fields('korean_traditional', 'takju'), ['appearance_texture']);
    expect(fields('sake', 'junmai'), isEmpty);
    expect(fields('korean_traditional', 'distilled_soju'), isEmpty);
  });

  test('a sparkling wine is read on the white wine\'s colours, each with its '
      'colour value', () {
    final sparkling = choices.forDrink('wine', 'sparkling_wine').first;
    final white = choices.forDrink('wine', 'white_wine').first;
    expect(
      sparkling.options.map((option) => option.key),
      white.options.map((option) => option.key),
    );
    expect(white.options.first.label, '물빛');
    expect(white.options.first.swatch, 0xFFF9F9F0);
  });

  test('the textures name the drawings the 테이스팅 노트 has', () {
    final texture = choices.forDrink('wine', 'red_wine').last;
    expect(texture.options.map((option) => option.icon), [
      'legs_light',
      'legs_medium',
      'legs_heavy',
    ]);
    final takju = choices.forDrink('korean_traditional', 'takju').single;
    expect(takju.label, '탁도');
    expect(takju.options.map((option) => option.icon), [
      'sediment_low',
      'sediment_mid',
      'sediment_high',
    ]);
  });
}
