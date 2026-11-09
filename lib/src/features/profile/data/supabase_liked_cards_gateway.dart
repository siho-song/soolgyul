import 'package:supabase_flutter/supabase_flutter.dart';

import 'liked_cards_gateway.dart';
import '../../../core/supabase/signed_in.dart';
import '../../catalog/data/catalog_photos.dart';

class SupabaseLikedCardsGateway implements LikedCardsGateway {
  const SupabaseLikedCardsGateway(this._client);
  final SupabaseClient _client;
  static const pageSize = 30;

  String get _userId => signedInUserId(_client);

  @override
  Future<LikedCardsPage> fetch({
    String? category,
    bool latestFirst = true,
    int offset = 0,
  }) async {
    final userId = _userId;
    // Catalog tables are not client-readable, so the owner RPC joins the
    // record, catalog name and interest key and returns one page plus total.
    final response =
        await _client.rpc(
              'soolgyul_my_liked_cards',
              params: {
                'p_category': category,
                'p_latest_first': latestFirst,
                'p_offset': offset,
                'p_limit': pageSize,
              },
            )
            as Map<String, dynamic>;
    final rows = (response['cards'] as List).cast<Map<String, dynamic>>();
    final itemIds = rows
        .map((row) => row['alcohol_item_id'])
        .whereType<String>()
        .toSet();
    final images = await catalogPhotoUrls(_client, itemIds);
    if (_userId != userId) throw StateError('로그인 계정이 변경되었습니다.');
    return LikedCardsPage(
      total: response['total'] as int,
      cards: [for (final row in rows) _parse(row, images)],
    );
  }

  LikedCard _parse(Map<String, dynamic> row, Map<String, String> images) {
    final note = (row['note'] as String?)?.trim();
    return LikedCard(
      id: row['drink_record_id'] as String,
      title: row['name'] as String,
      description: note == null || note.isEmpty ? '좋아요한 술결 카드예요.' : note,
      category: row['interest_key'] as String? ?? 'other',
      recordedAt: DateTime.parse(row['recorded_at'] as String).toLocal(),
      imageUrl: images[row['alcohol_item_id']],
    );
  }

  @override
  Future<bool> isLiked(String cardId) async {
    final userId = _userId;
    final rows = await _client
        .from('user_liked_drink_cards')
        .select('drink_record_id')
        .eq('user_id', userId)
        .eq('drink_record_id', cardId)
        .limit(1);
    if (_userId != userId) throw StateError('로그인 계정이 변경되었습니다.');
    return rows.isNotEmpty;
  }

  @override
  Future<void> like(String cardId) async {
    final userId = _userId;
    // Ignore repeats without changing the original liked timestamp. UPDATE is
    // intentionally not granted on this owner-only relationship table.
    await _client
        .from('user_liked_drink_cards')
        .upsert(
          {'user_id': userId, 'drink_record_id': cardId},
          onConflict: 'user_id,drink_record_id',
          ignoreDuplicates: true,
        );
    if (_userId != userId || !await isLiked(cardId)) {
      throw StateError('좋아요 저장 결과를 확인하지 못했습니다.');
    }
  }

  @override
  Future<void> unlike(String cardId) async {
    final userId = _userId;
    // Deleting an already-removed favorite is intentionally idempotent.
    // The card and its drink record are never deleted here.
    await _client
        .from('user_liked_drink_cards')
        .delete()
        .eq('user_id', userId)
        .eq('drink_record_id', cardId);
    if (_userId != userId) throw StateError('로그인 계정이 변경되었습니다.');
  }
}
