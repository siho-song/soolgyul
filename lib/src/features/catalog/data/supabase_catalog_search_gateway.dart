import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_report.dart';
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
      final response =
          await _rpcInvoker('soolgyul_search_catalog', <String, dynamic>{
            'target_query': normalizedQuery,
            'target_limit': limit.clamp(1, catalogSearchPageSize),
            'target_offset': offset < 0 ? 0 : offset,
          });
      final rows = response is Map ? response['results'] : null;
      if (rows is! List) {
        throw const FormatException('the search results are not a list');
      }
      final fields = <Map<String, dynamic>>[
        for (final row in rows)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      final notCarried = (response as Map)['not_carried'];
      return CatalogMatches(
        [for (final row in fields) ?_drinkFromRow(row)],
        guesses: fields.isNotEmpty && fields.first['match_kind'] != 'exact',
        notCarried: notCarried is String ? notCarried : null,
      );
    } catch (error, stack) {
      _failed(error, stack);
    }
  }

  @override
  Future<List<List<CatalogDrink>>> searchMany(
    List<String> queries, {
    int limit = 10,
    bool readOffLabel = false,
  }) async {
    final answers = List<List<CatalogDrink>>.generate(
      queries.length,
      (_) => <CatalogDrink>[],
    );
    if (queries.isEmpty) return answers;
    try {
      final response = await _rpcInvoker(
        readOffLabel
            ? 'soolgyul_search_alcohol_catalog_by_label'
            : 'soolgyul_search_alcohol_catalog_batch',
        <String, dynamic>{
          'target_queries': queries,
          'target_limit': limit.clamp(1, catalogSearchPageSize),
        },
      );
      if (response is! List) {
        throw const FormatException('the search results are not a list');
      }
      for (final row in response) {
        if (row is! Map) continue;
        // query_index counts from one.
        final index = row['query_index'] is int
            ? (row['query_index'] as int) - 1
            : -1;
        final drink = _drinkFromRow(Map<String, dynamic>.from(row));
        if (index < 0 || index >= answers.length || drink == null) continue;
        answers[index].add(drink);
      }
      return answers;
    } catch (error, stack) {
      // A server that does not have the label search yet answers as it
      // does for typed names.
      if (readOffLabel &&
          error is PostgrestException &&
          error.code == _functionMissing) {
        return searchMany(queries, limit: limit);
      }
      _failed(error, stack);
    }
  }

  /// PostgREST's code for a function it cannot find.
  static const String _functionMissing = 'PGRST202';

  /// A refusal from the server or a phone without a network is ordinary;
  /// anything else is a fault of the app or the answer and is reported.
  static Never _failed(Object error, StackTrace stack) {
    if (error is! PostgrestException) {
      reportError(error, stack, where: 'catalog search');
    }
    throw const CatalogSearchException();
  }

  /// Null for a row without the id, name or category a drink is shown by;
  /// the rest of the page still shows.
  CatalogDrink? _drinkFromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['name_ko'];
    final categoryKey = row['category_key'];
    if (id is! String || name is! String || categoryKey is! String) {
      return null;
    }
    final style = row['style_key'];
    final styleKey = style is String ? style : null;
    final abv = row['abv_percent'];
    final nameEn = row['name_en'];
    final styleLabel = row['style_label'];
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
      photoUrl: catalogPhotoUrl(_client, row['media_path']),
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
