import 'package:flutter/foundation.dart';

import '../../profile/data/account_completion_draft.dart';
import 'catalog_drink.dart';
import 'catalog_search_gateway.dart';

// The 자주 찾는 술 under each search field before anything is typed: a tap
// on one does what a tap on a search result does on that screen. The list
// follows the member's gender: three bottles from what each group buys more
// of (card and convenience-store sales: single malts for men in their 20s;
// moscato, chardonnay and takju for women), then two shared ones. A guest,
// whose gender is unknown, sees the men's list. Each entry is the exact
// catalog `name_ko`; names missing from the catalog are skipped.

const List<String> maleSuggestedDrinkNames = <String>[
  '발베니 더블우드 12년',
  '글렌피딕 15년',
  '화요 25',
  '조니워커 블랙 라벨',
  '닷사이 준마이 다이긴죠 45',
];

const List<String> femaleSuggestedDrinkNames = <String>[
  '칸티 모스카토 다스티 DOCG',
  '몬테스 알파 샤르도네',
  '복순도가 손막걸리',
  '조니워커 블랙 라벨',
  '닷사이 준마이 다이긴죠 45',
];

/// The 자주 찾는 술 for a member of [gender]; `null` is a guest.
List<String> suggestedDrinkNamesFor(ProfileGender? gender) =>
    gender == ProfileGender.female
    ? femaleSuggestedDrinkNames
    : maleSuggestedDrinkNames;

/// Resolves suggested drink names to catalog drinks once per app session.
///
/// The app calls [load] as soon as it knows whose list to show, so the list
/// is ready the moment a search page opens; both lists share what was
/// looked up. All names still unknown go out in one call.
abstract final class SuggestedDrinks {
  static final Map<String, CatalogDrink?> _resolved = <String, CatalogDrink?>{};
  static final Map<String, Future<void>> _pending = <String, Future<void>>{};

  /// The resolved list when every name was already looked up, else `null`.
  static List<CatalogDrink>? cached(List<String> names) {
    if (!names.every(_resolved.containsKey)) {
      return null;
    }
    return List<CatalogDrink>.unmodifiable(
      names.map((name) => _resolved[name]).whereType<CatalogDrink>(),
    );
  }

  static Future<List<CatalogDrink>> load(
    CatalogSearchGateway gateway,
    List<String> names,
  ) async {
    final unknown = <String>[
      for (final name in names)
        if (!_resolved.containsKey(name) && !_pending.containsKey(name)) name,
    ];
    if (unknown.isNotEmpty) {
      final lookup = _resolve(gateway, unknown);
      for (final name in unknown) {
        _pending[name] = lookup;
      }
    }
    await Future.wait(names.map((name) => _pending[name]).nonNulls);
    return List<CatalogDrink>.unmodifiable(
      names.map((name) => _resolved[name]).whereType<CatalogDrink>(),
    );
  }

  static Future<void> _resolve(
    CatalogSearchGateway gateway,
    List<String> names,
  ) async {
    try {
      final answers = await gateway.searchMany(names, limit: 5);
      for (var index = 0; index < names.length; index++) {
        CatalogDrink? match;
        for (final drink in answers[index]) {
          if (drink.displayName == names[index]) {
            match = drink;
            break;
          }
        }
        // A name the catalog does not carry is remembered as missing.
        _resolved[names[index]] = match;
      }
    } catch (_) {
      // A failed lookup is left out now and retried on the next load.
    } finally {
      names.forEach(_pending.remove);
    }
  }

  @visibleForTesting
  static void clear() {
    _resolved.clear();
    _pending.clear();
  }
}
