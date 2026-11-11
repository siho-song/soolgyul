import 'catalog_drink.dart';
import 'catalog_search_gateway.dart';

/// Keeps the answers of the latest searches for a few minutes. Typing a
/// name again, deleting back to an earlier spelling or returning to a page
/// already shown then asks the server nothing. The catalog changes by a
/// sync a few times a week, so an answer ten minutes old is as good as a
/// fresh one. A failed search is not kept.
class RememberedCatalogSearch implements CatalogSearchGateway {
  RememberedCatalogSearch(
    this._inner, {
    this.keptFor = const Duration(minutes: 10),
    this.capacity = 60,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CatalogSearchGateway _inner;
  final Duration keptFor;

  /// How many answers are kept; the one asked for longest ago goes first.
  final int capacity;
  final DateTime Function() _now;

  /// In the order they were last asked for.
  final Map<String, ({DateTime at, List<CatalogDrink> drinks})> _answers =
      <String, ({DateTime at, List<CatalogDrink> drinks})>{};

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = catalogSearchPageSize,
    int offset = 0,
  }) async {
    final key = '${query.trim()}\n$limit\n$offset';
    final kept = _answers.remove(key);
    if (kept != null && _now().difference(kept.at) < keptFor) {
      _answers[key] = kept;
      return kept.drinks;
    }
    final drinks = await _inner.search(query, limit: limit, offset: offset);
    _answers[key] = (at: _now(), drinks: drinks);
    if (_answers.length > capacity) _answers.remove(_answers.keys.first);
    return drinks;
  }

  /// Passed through: the callers of this keep their own answers.
  @override
  Future<List<List<CatalogDrink>>> searchMany(
    List<String> queries, {
    int limit = 10,
    bool readOffLabel = false,
  }) => _inner.searchMany(queries, limit: limit, readOffLabel: readOffLabel);
}
