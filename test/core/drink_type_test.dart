import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/catalog/drink_type.dart';
import 'package:soolgyul/src/core/format/abv.dart';
import 'package:soolgyul/src/core/format/korean_particles.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/glossary/data/saved_terms.dart';
import 'package:soolgyul/src/features/profile/data/drink_interest_catalog.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';

void main() {
  test('the four 주종 carry their server key and the name the app shows', () {
    expect(
      [for (final type in DrinkType.values) (type.key, type.label)],
      [
        ('wine', '와인'),
        ('whisky', '위스키'),
        ('sake', '사케'),
        ('korean_traditional', '전통주'),
      ],
    );
    expect(DrinkType.fromKey('sake'), DrinkType.sake);
    expect(DrinkType.fromKey('beer'), isNull);
    expect(DrinkType.fromKey(null), isNull);
  });

  test('every list of 주종 takes its key and name from the one list', () {
    expect([
      for (final option in drinkInterestOptions) option.value,
    ], DrinkType.values);
    expect(TermDrink.common.wire, 'common');
    expect(
      [for (final drink in TermDrink.values) drink.type].nonNulls.toList(),
      DrinkType.values,
    );
    expect(DrinkCategory.sparklingWine.type, DrinkType.wine);
    expect(DrinkCategory.other.type, isNull);
  });

  test('a strength drops the decimal of a whole number', () {
    expect(formatAbv(40), '40%');
    expect(formatAbv(11.5), '11.5%');
  });

  test('a particle follows whether the last syllable closes', () {
    expect(endsOnConsonant('와인'), isTrue);
    expect(endsOnConsonant('위스키'), isFalse);
    expect(endsOnConsonant('Sake'), isFalse);
    expect(endsOnConsonant(''), isFalse);
  });

  test('a tag kind is read by the key the server sends', () {
    expect(TasteCardTagKind.fromKey('burden'), TasteCardTagKind.burden);
    expect(TasteCardTagKind.fromKey('other'), isNull);
    expect(TasteCardTagKind.fromKey(null), isNull);
  });
}
