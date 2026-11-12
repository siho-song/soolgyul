import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/signed_in.dart';
import '../../catalog/data/catalog_drink_row.dart';
import 'saved_drinks_gateway.dart';
import 'taste_fit_verdict.dart';

class SupabaseSavedDrinksGateway implements SavedDrinksGateway {
  const SupabaseSavedDrinksGateway(this._client);
  final SupabaseClient _client;
  static const pageSize = 30;

  String get _userId => signedInUserId(_client);

  @override
  Future<SavedDrinksPage> fetch({int offset = 0}) async {
    final userId = _userId;
    // Catalog tables are not client-readable, so the owner RPC joins each
    // saved bottle with what a search row carries.
    final response =
        await _client.rpc(
              'soolgyul_my_saved_drinks',
              params: {'p_offset': offset, 'p_limit': pageSize},
            )
            as Map<String, dynamic>;
    if (_userId != userId) throw StateError('the signed-in account changed');
    return SavedDrinksPage(
      total: response['total'] as int,
      drinks: [
        for (final row in response['drinks'] as List)
          if (row is Map)
            ?catalogDrinkFromRow(_client, Map<String, dynamic>.from(row)),
      ],
    );
  }

  @override
  Future<bool> isSaved(String drinkId) async {
    final userId = _userId;
    final rows = await _client
        .from('user_saved_drinks')
        .select('alcohol_item_id')
        .eq('user_id', userId)
        .eq('alcohol_item_id', drinkId)
        .limit(1);
    if (_userId != userId) throw StateError('the signed-in account changed');
    return rows.isNotEmpty;
  }

  @override
  Future<void> save(String drinkId, {TasteFitBadge? badge}) async {
    _userId;
    await _client.rpc(
      'soolgyul_save_my_drink',
      params: {'p_alcohol_item_id': drinkId, 'p_fit_badge': badge?.wire},
    );
  }

  @override
  Future<void> unsave(String drinkId) async {
    _userId;
    await _client.rpc(
      'soolgyul_unsave_my_drink',
      params: {'p_alcohol_item_id': drinkId},
    );
  }
}
