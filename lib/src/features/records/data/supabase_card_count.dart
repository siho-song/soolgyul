import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/signed_in.dart';

/// Counts the signed-in account's records that have a card.
class SupabaseCardCount {
  const SupabaseCardCount(this._client);
  final SupabaseClient _client;

  Future<int> load() async {
    // Matching rows are counted, none is read; the inner join leaves out a
    // record whose card the account cannot read.
    final records = await askAsSignedIn(
      _client,
      (userId) => _client
          .from('drink_records')
          .select('id,taste_cards!inner(id)')
          .eq('user_id', userId)
          .limit(0)
          .count(CountOption.exact),
    );
    return records.count;
  }
}
