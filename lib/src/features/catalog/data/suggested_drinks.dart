import 'package:flutter/foundation.dart';

import 'catalog_drink.dart';
import 'catalog_search_gateway.dart';

// The 자주 찾는 술 under each search field before anything is typed: a tap
// on one does what a tap on a search result does on that screen. One widely
// sold bottle per catalog category, picked by hand (news coverage of
// convenience-store and mart sales, Nov 2026). Each entry is the exact
// catalog `name_ko`; names missing from the catalog are skipped. The two
// lists start alike and may part.

/// Under the record search: the first drink and every record after it.
const List<String> recordSuggestedDrinkNames = <String>[
  '조니워커 블랙 라벨',
  '화요 25',
  '몬테스 알파 까베르네 소비뇽',
  '닷사이 준마이 다이긴죠 45',
  '복순도가 탁주',
];

/// Under 나랑 맞는 술 찾기, each with its taste-fit verdict.
const List<String> tasteFitSuggestedDrinkNames = <String>[
  '조니워커 블랙 라벨',
  '화요 25',
  '몬테스 알파 까베르네 소비뇽',
  '닷사이 준마이 다이긴죠 45',
  '복순도가 탁주',
];

/// Resolves suggested drink names to catalog drinks once per app session.
///
/// The page before the record search calls [load] so the list is ready the
/// moment the search page opens; both lists share what was looked up.
abstract final class SuggestedDrinks {
  static final Map<String, CatalogDrink?> _resolved = <String, CatalogDrink?>{};
  static final Map<String, Future<CatalogDrink?>> _pending =
      <String, Future<CatalogDrink?>>{};

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
    final drinks = await Future.wait(
      names.map((name) {
        if (_resolved.containsKey(name)) {
          return Future<CatalogDrink?>.value(_resolved[name]);
        }
        return _pending[name] ??= _resolve(gateway, name);
      }),
    );
    return List<CatalogDrink>.unmodifiable(drinks.whereType<CatalogDrink>());
  }

  static Future<CatalogDrink?> _resolve(
    CatalogSearchGateway gateway,
    String name,
  ) async {
    try {
      final matches = await gateway.search(name, limit: 5);
      CatalogDrink? match;
      for (final drink in matches) {
        if (drink.displayName == name) {
          match = drink;
          break;
        }
      }
      // A name the catalog does not carry is remembered as missing.
      _resolved[name] = match;
      return match;
    } catch (_) {
      // A failed lookup is left out now and retried on the next load.
      return null;
    } finally {
      _pending.remove(name);
    }
  }

  @visibleForTesting
  static void clear() {
    _resolved.clear();
    _pending.clear();
  }
}
