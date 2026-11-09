import 'package:supabase_flutter/supabase_flutter.dart';

import 'catalog_drink.dart';
import 'catalog_search_gateway.dart';
import 'catalog_photos.dart';

typedef CatalogSearchRpcInvoker =
    Future<dynamic> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );

class SupabaseCatalogSearchGateway implements CatalogSearchGateway {
  SupabaseCatalogSearchGateway(
    SupabaseClient client, {
    CatalogSearchRpcInvoker? rpcInvoker,
  }) : _client = client,
       _rpcInvoker =
           rpcInvoker ??
           ((functionName, parameters) async {
             return await client.rpc(functionName, params: parameters);
           });

  final SupabaseClient _client;
  final CatalogSearchRpcInvoker _rpcInvoker;

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = catalogSearchPageSize,
    int offset = 0,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <CatalogDrink>[];
    }
    try {
      final response = await _rpcInvoker(
        'soolgyul_search_alcohol_catalog',
        <String, dynamic>{
          'target_query': normalizedQuery,
          'target_limit': limit.clamp(1, catalogSearchPageSize),
          'target_offset': offset < 0 ? 0 : offset,
        },
      );
      if (response is! List) {
        throw const CatalogSearchException();
      }
      return List<CatalogDrink>.unmodifiable(
        response.map(
          (row) => _drinkFromRow(Map<String, dynamic>.from(row as Map)),
        ),
      );
    } catch (error) {
      if (error is CatalogSearchException) {
        rethrow;
      }
      throw const CatalogSearchException();
    }
  }

  CatalogDrink _drinkFromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['name_ko'];
    final categoryKey = row['category_key'];
    if (id is! String || name is! String || categoryKey is! String) {
      throw const CatalogSearchException();
    }
    final styleKey = row['style_key'] as String?;
    final abv = row['abv_percent'];
    final nameEn = row['name_en'];
    final styleLabel = row['style_label'];
    final mediaPath = row['media_path'];
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    return CatalogDrink(
      id: id,
      displayName: name,
      nameEn: text(nameEn),
      countryCode: text(row['country_code']),
      region: text(row['region']),
      category: _drinkCategory(categoryKey, styleKey),
      styleLabel: styleLabel is String && styleLabel.isNotEmpty
          ? styleLabel
          : null,
      abvPercent: abv is num ? abv.toDouble() : null,
      photoUrl: mediaPath is String && mediaPath.isNotEmpty
          ? _client.storage.from(catalogImageBucket).getPublicUrl(mediaPath)
          : null,
    );
  }
}

DrinkCategory _drinkCategory(String categoryKey, String? styleKey) {
  if (categoryKey == 'wine') {
    return switch (styleKey) {
      'red_wine' => DrinkCategory.redWine,
      'white_wine' => DrinkCategory.whiteWine,
      'sparkling_wine' => DrinkCategory.sparklingWine,
      _ => DrinkCategory.other,
    };
  }
  return switch (categoryKey) {
    'whisky' => DrinkCategory.whisky,
    'sake' => DrinkCategory.sake,
    'korean_traditional' => DrinkCategory.koreanTraditional,
    _ => DrinkCategory.other,
  };
}
