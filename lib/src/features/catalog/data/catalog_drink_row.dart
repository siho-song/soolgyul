import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/catalog/drink_type.dart';
import 'catalog_drink.dart';
import 'catalog_photos.dart';

/// A drink from one row the server answers a catalog read with: a search
/// result or a saved bottle. Null for a row without the id, name or
/// category a drink is shown by; the rest of the list still shows.
CatalogDrink? catalogDrinkFromRow(
  SupabaseClient client,
  Map<String, dynamic> row,
) {
  final id = row['id'];
  final name = row['name_ko'];
  final categoryKey = row['category_key'];
  if (id is! String || name is! String || categoryKey is! String) {
    return null;
  }
  final style = row['style_key'];
  final styleKey = style is String ? style : null;
  final abv = row['abv_percent'];
  final styleLabel = row['style_label'];
  String? text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
  return CatalogDrink(
    id: id,
    displayName: name,
    nameEn: text(row['name_en']),
    countryCode: text(row['country_code']),
    region: text(row['region']),
    category: _drinkCategory(categoryKey, styleKey),
    styleLabel: styleLabel is String && styleLabel.isNotEmpty
        ? styleLabel
        : null,
    abvPercent: abv is num ? abv.toDouble() : null,
    photoUrl: catalogPhotoUrl(client, row['media_path']),
    labelFacts: DrinkLabelFacts.fromJson(row['label_facts']),
  );
}

DrinkCategory _drinkCategory(String categoryKey, String? styleKey) {
  return switch (DrinkType.fromKey(categoryKey)) {
    DrinkType.wine => switch (styleKey) {
      'red_wine' => DrinkCategory.redWine,
      'white_wine' => DrinkCategory.whiteWine,
      'sparkling_wine' => DrinkCategory.sparklingWine,
      _ => DrinkCategory.other,
    },
    DrinkType.whisky => DrinkCategory.whisky,
    DrinkType.sake => DrinkCategory.sake,
    DrinkType.koreanTraditional => DrinkCategory.koreanTraditional,
    null => DrinkCategory.other,
  };
}
