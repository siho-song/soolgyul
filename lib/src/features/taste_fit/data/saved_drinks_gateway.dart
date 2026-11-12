import '../../catalog/data/catalog_drink.dart';
import 'taste_fit_verdict.dart';

/// One page of the bottles the reader saved, newest first, and how many
/// there are in all.
class SavedDrinksPage {
  const SavedDrinksPage({required this.drinks, required this.total});
  final List<CatalogDrink> drinks;
  final int total;
}

/// 저장한 술: the bottles a member keeps from the fit page to come back to.
abstract interface class SavedDrinksGateway {
  Future<SavedDrinksPage> fetch({int offset = 0});

  Future<bool> isSaved(String drinkId);

  /// [badge] is the verdict the fit page shows for the bottle right now;
  /// `null` when it shows none.
  Future<void> save(String drinkId, {TasteFitBadge? badge});

  Future<void> unsave(String drinkId);
}
