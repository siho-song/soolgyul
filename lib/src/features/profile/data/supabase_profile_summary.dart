import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_summary.dart';
import '../../../core/supabase/signed_in.dart';

class SupabaseProfileSummary {
  const SupabaseProfileSummary(this._client);
  final SupabaseClient _client;

  Future<ProfileSummary> load() async {
    final userId = signedInUserId(_client);

    // Count matching rows only. Inner joins omit deleted/inaccessible cards
    // and unpublished articles.
    final records = await _client
        .from('drink_records')
        .select('id,taste_cards!inner(id)')
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .limit(0)
        .count(CountOption.exact);
    final saved = await _client
        .from('user_saved_articles')
        .select('article_id,editorial_articles!inner(id)')
        .eq('user_id', userId)
        .eq('editorial_articles.status', 'published')
        .limit(0)
        .count(CountOption.exact);
    final liked = await _client
        .from('user_liked_drink_cards')
        .select('drink_record_id,drink_records!inner(id)')
        .eq('user_id', userId)
        .eq('drink_records.user_id', userId)
        .isFilter('drink_records.deleted_at', null)
        .limit(0)
        .count(CountOption.exact);
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('the signed-in account changed');
    }
    return ProfileSummary(
      cardCount: records.count,
      savedArticleCount: saved.count,
      likedCardCount: liked.count,
    );
  }
}
