import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_report.dart';
import 'catalog_drink.dart';
import 'catalog_drink_row.dart';
import 'catalog_search_gateway.dart';

typedef CatalogSearchRpcInvoker =
    Future<dynamic> Function(
      String functionName,
      Map<String, dynamic> parameters,
    );

/// Asks the server's label judge: the function's body in, its answer out.
/// `null` when nobody is signed in, whom alone the function answers.
typedef LabelPickInvoker = Future<dynamic> Function(Map<String, dynamic> body);

class SupabaseCatalogSearchGateway
    implements CatalogSearchGateway, LabelWordSearch, LabelPhotoJudge {
  SupabaseCatalogSearchGateway(
    SupabaseClient client, {
    CatalogSearchRpcInvoker? rpcInvoker,
    LabelPickInvoker? Function()? labelPickInvoker,
  }) : _client = client,
       _rpcInvoker =
           rpcInvoker ??
           ((functionName, parameters) async {
             return await client.rpc(functionName, params: parameters);
           }),
       _labelPickInvoker =
           labelPickInvoker ??
           (() => client.auth.currentSession == null
               ? null
               : (body) async => (await client.functions.invoke(
                   'label-pick',
                   body: body,
                 )).data);

  final SupabaseClient _client;
  final CatalogSearchRpcInvoker _rpcInvoker;
  final LabelPickInvoker? Function() _labelPickInvoker;

  /// How long a reader waits for the judge before the label match's own
  /// answer shows. The judge mostly answers in two seconds, in six when it
  /// also looks at the catalog's photo.
  static const Duration _judgeWait = Duration(seconds: 8);

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

  @override
  Future<List<LabelCandidate>> searchByLabelWords(
    List<String> words, {
    List<String> alsoIds = const <String>[],
  }) async {
    if (words.isEmpty && alsoIds.isEmpty) return const <LabelCandidate>[];
    try {
      final response = await _rpcInvoker(
        'soolgyul_search_alcohol_catalog_by_label_words',
        <String, dynamic>{'target_words': words, 'also_ids': alsoIds},
      );
      if (response is! List) {
        throw const FormatException('the search results are not a list');
      }
      return <LabelCandidate>[
        for (final row in response)
          if (row is Map) ?_candidateFromRow(Map<String, dynamic>.from(row)),
      ];
    } catch (error, stack) {
      // A server without the word search leaves the line search's answer.
      if (error is PostgrestException && error.code == _functionMissing) {
        return const <LabelCandidate>[];
      }
      _failed(error, stack);
    }
  }

  @override
  Future<String?> pickByPhoto(
    Uint8List photo,
    List<String> candidateIds, {
    required bool appSure,
  }) async {
    final invoke = _labelPickInvoker();
    if (invoke == null || candidateIds.isEmpty) {
      throw const LabelPhotoJudgeException();
    }
    try {
      final answer = await invoke(<String, dynamic>{
        'photo': base64Encode(photo),
        'candidate_ids': candidateIds
            .take(LabelPhotoJudge.maxCandidates)
            .toList(growable: false),
        'app_sure': appSure,
      }).timeout(_judgeWait);
      if (answer is! Map || !answer.containsKey('drink_id')) {
        throw const FormatException('the label pick names no drink_id');
      }
      final drinkId = answer['drink_id'];
      return drinkId is String ? drinkId : null;
    } catch (error, stack) {
      // A refusal, a slow answer or a phone without a network is ordinary.
      if (error is! FunctionException &&
          error is! TimeoutException &&
          error is! AuthException) {
        reportError(error, stack, where: 'label pick');
      }
      throw const LabelPhotoJudgeException();
    }
  }

  LabelCandidate? _candidateFromRow(Map<String, dynamic> row) {
    final drink = _drinkFromRow(row);
    final kind = row['category_key'];
    final rarity = row['name_rarity'];
    final found = row['found'];
    if (drink == null || kind is! String) return null;
    return LabelCandidate(
      drink: drink,
      kind: kind,
      nameRarity: <String, double>{
        if (rarity is Map)
          for (final MapEntry(:key, :value) in rarity.entries)
            if (key is String && value is num) key: value.toDouble(),
      },
      found: found is num ? found.toDouble() : 0,
    );
  }

  /// PostgREST's code for a function it cannot find.
  static const String _functionMissing = 'PGRST202';

  /// A refusal from the server or a phone without a network is ordinary;
  /// anything else is a fault of the app or the answer and is reported.
  static Never _failed(Object error, StackTrace stack) {
    if (error is! PostgrestException) {
      reportError(error, stack, where: 'catalog search');
    }
    throw CatalogSearchException(cause: error);
  }

  CatalogDrink? _drinkFromRow(Map<String, dynamic> row) =>
      catalogDrinkFromRow(_client, row);
}
