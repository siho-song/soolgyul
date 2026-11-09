import '../catalog_drink.dart';

/// How many matches one search call returns; a full page means more may follow.
const int catalogSearchPageSize = 20;

abstract interface class CatalogSearchGateway {
  /// [offset] skips the matches already shown, for the next page.
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = catalogSearchPageSize,
    int offset = 0,
  });
}

class CatalogSearchException implements Exception {
  const CatalogSearchException();
}
