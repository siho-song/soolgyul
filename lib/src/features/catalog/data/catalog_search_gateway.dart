import 'catalog_drink.dart';

/// How many matches one search call returns; a full page means more may follow.
const int catalogSearchPageSize = 20;

abstract interface class CatalogSearchGateway {
  /// [offset] skips the matches already shown, for the next page.
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = catalogSearchPageSize,
    int offset = 0,
  });

  /// One answer per query, in order, from a single call: what [search]
  /// would return for each, up to [limit] drinks. At most eight queries.
  Future<List<List<CatalogDrink>>> searchMany(
    List<String> queries, {
    int limit = 10,
  });
}

class CatalogSearchException implements Exception {
  const CatalogSearchException();
}
