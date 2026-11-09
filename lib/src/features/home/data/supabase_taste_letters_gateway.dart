import 'package:supabase_flutter/supabase_flutter.dart';

import 'taste_letters.dart';

class SupabaseTasteLettersGateway implements TasteLettersGateway {
  const SupabaseTasteLettersGateway(this._client);
  final SupabaseClient _client;

  String get _userId =>
      _client.auth.currentUser?.id ?? (throw StateError('로그인이 필요합니다.'));

  @override
  Future<TasteLettersSnapshot> load() async {
    final userId = _userId;
    final letterRows = await _client
        .from('taste_letters')
        .select('axes,record_count,updated_at')
        .eq('user_id', userId)
        .limit(1);
    if (letterRows.isEmpty) return const TasteLettersSnapshot();
    final changeRows = await _client
        .from('taste_letter_changes')
        .select(
          'axis,from_letter,to_letter,left_share,right_share,'
          'product_name,changed_at,drink_record_id',
        )
        .eq('user_id', userId)
        .order('changed_at', ascending: true);
    final cardIds = await _cardIdsOf(<String>{
      for (final row in changeRows)
        if (row['drink_record_id'] case final String id) id,
    });
    if (_userId != userId) throw StateError('로그인 계정이 변경되었습니다.');
    return TasteLettersSnapshot(
      state: TasteLettersState.fromRow(letterRows.first),
      changes: [
        for (final row in changeRows)
          ?TasteLetterChange.fromRow(
            row,
            resultId: cardIds[row['drink_record_id']],
          ),
      ],
    );
  }

  /// The saved card of each record; a deleted record has none.
  Future<Map<String, String>> _cardIdsOf(Set<String> recordIds) async {
    if (recordIds.isEmpty) return const <String, String>{};
    final rows = await _client
        .from('taste_cards')
        .select('id,drink_record_id')
        .inFilter('drink_record_id', recordIds.toList());
    return <String, String>{
      for (final row in rows)
        row['drink_record_id'] as String: row['id'] as String,
    };
  }
}
