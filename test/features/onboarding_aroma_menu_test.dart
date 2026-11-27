import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';

import '../support/sensory_fixtures.dart';

// The aroma question's menus: which one a drink is asked by, and that they
// draw exactly the aromas the dictionary offers.

void main() {
  final vocabulary = serviceVocabulary();

  /// The aromas the dictionary offers a reader.
  final offered = sensoryRegistry().aromaKeys;

  group('onboarding aroma menu', () {
    // Every kind the dictionary names, with the menu its drinks are asked.
    const menuOfKind = {
      'red_wine': 'wine_red',
      'white_wine': 'wine_white_sparkling_rose',
      'sparkling_wine': 'wine_white_sparkling_rose',
      'rose_wine': 'wine_white_sparkling_rose',
      'orange_wine': 'wine_white_sparkling_rose',
      'fortified_wine': 'wine_fortified',
      'port_wine': 'wine_fortified',
      'sherry_wine': 'wine_fortified',
      'madeira_wine': 'wine_fortified',
      'vermouth': 'wine_fortified',
      'single_malt_whisky': 'whisky_malt_blended',
      'blended_whisky': 'whisky_malt_blended',
      'blended_malt_whisky': 'whisky_malt_blended',
      'single_pot_still_whisky': 'whisky_malt_blended',
      'grain_whisky': 'whisky_malt_blended',
      'bourbon': 'whisky_american',
      'rye_whisky': 'whisky_american',
      'tennessee_whisky': 'whisky_american',
      'corn_whisky': 'whisky_american',
      'wheat_whisky': 'whisky_american',
      'american_whisky': 'whisky_american',
      'junmai': 'sake',
      'ginjo': 'sake',
      'daiginjo': 'sake',
      'junmai_ginjo': 'sake',
      'junmai_daiginjo': 'sake',
      'honjozo': 'sake',
      'futsushu': 'sake',
      'takju': 'korean_takju_yakju',
      'yakju': 'korean_takju_yakju',
      'korean_cheongju': 'korean_takju_yakju',
      'gwahaju': 'korean_takju_yakju',
      'distilled_soju': 'korean_distilled_soju',
      'diluted_soju': 'korean_distilled_soju',
      'korean_fruit_wine': 'korean_fruit_wine',
    };
    final categoryOfKind = {
      for (final row
          in readJsonAsset(
                'config/catalog/enrichment_taxonomy_v2.json',
              )['primary_styles']
              as List)
        row['style_key'] as String: row['category_key'] as String,
    };
    final menus = {
      for (final entry in categoryOfKind.entries)
        OnboardingAromaMenu.forDrink(entry.value, entry.key),
    };

    test('a drink gets the menu of its category and kind', () {
      expect(menuOfKind.keys.toSet(), categoryOfKind.keys.toSet());
      for (final entry in menuOfKind.entries) {
        expect(
          OnboardingAromaMenu.forDrink(
            categoryOfKind[entry.key],
            entry.key,
          ).name,
          entry.value,
          reason: entry.key,
        );
      }
      expect(menus.map((menu) => menu.name).toSet(), hasLength(9));
      // No kind, or one the category does not have: its widest menu.
      for (final style in [null, 'unknown', 'bourbon']) {
        expect(OnboardingAromaMenu.forDrink('wine', style).name, 'wine_red');
        expect(OnboardingAromaMenu.forDrink('sake', style).name, 'sake');
        expect(
          OnboardingAromaMenu.forDrink('korean_traditional', style).name,
          'korean_takju_yakju',
        );
      }
      for (final style in [null, 'unknown', 'white_wine']) {
        expect(
          OnboardingAromaMenu.forDrink('whisky', style).name,
          'whisky_malt_blended',
        );
      }
      // Any other category is asked as a malt whisky.
      for (final category in [null, 'unknown', 'beer']) {
        expect(
          OnboardingAromaMenu.forDrink(category, 'bourbon').name,
          'whisky_malt_blended',
        );
      }
    });

    test('every menu chip stores a selectable dictionary key, once', () {
      for (final menu in menus) {
        final menuKeys = menu.keys.toList();
        expect(menuKeys.toSet(), hasLength(menuKeys.length), reason: menu.name);
        expect(offered, containsAll(menuKeys), reason: menu.name);
        expect(menu.groups, isNotEmpty);
        for (final group in menu.groups) {
          expect(group.title, isNotEmpty);
          expect(group.chips, isNotEmpty);
        }
      }
    });

    test('every menu key is offered by the dictionary, and the menus draw '
        'every offered aroma', () {
      // A chip holds no name: it is drawn under the dictionary's word.
      final words = {
        for (final group in vocabulary['groups'] as List)
          group['key'] as String: group['label_ko'] as String,
      };
      final inMenus = {for (final menu in menus) ...menu.keys};
      for (final key in inMenus) {
        expect(words[key], isNotEmpty, reason: key);
      }
      expect(inMenus, hasLength(125));
      // The aromas a reader is offered are those a menu draws, and no
      // other: a word nothing draws is not offered.
      expect(inMenus, offered);
      expect({for (final chip in OnboardingAromaMenu.chips) chip.key}, offered);
    });

    test('menus differ where the drinks do', () {
      Iterable<String> keysOf(String category, String? style) =>
          OnboardingAromaMenu.forDrink(category, style).keys;
      expect(keysOf('whisky', 'single_malt_whisky'), contains('peat'));
      expect(keysOf('whisky', 'bourbon'), isNot(contains('peat')));
      expect(keysOf('whisky', 'bourbon'), contains('corn'));
      expect(keysOf('wine', 'red_wine'), contains('blackberry'));
      expect(keysOf('wine', 'white_wine'), isNot(contains('blackberry')));
      expect(keysOf('wine', 'port_wine'), contains('raisin'));
      expect(keysOf('whisky', 'single_malt_whisky'), contains('sherry'));
      expect(keysOf('sake', 'junmai'), contains('nuruk'));
      expect(keysOf('sake', 'junmai'), isNot(contains('smoke')));
      expect(keysOf('korean_traditional', 'takju'), contains('mugwort'));
      expect(keysOf('korean_traditional', 'korean_fruit_wine').take(2), [
        'omija_bokbunja',
        'blackberry',
      ]);
    });
  });
}
