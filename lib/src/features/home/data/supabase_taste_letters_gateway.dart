import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/kept_first.dart';
import '../../../core/saved_views.dart';
import '../../../core/supabase/signed_in.dart';
import 'taste_letters.dart';

class SupabaseTasteLettersGateway
    implements TasteLettersGateway, KeepsLast<TasteLettersSnapshot> {
  const SupabaseTasteLettersGateway(this._client, {this.saved});
  final SupabaseClient _client;

  /// Where the last answer is kept for the next launch; `null` keeps none.
  final SavedViews? saved;
  static const _savedName = 'letters';

  String get _userId => signedInUserId(_client);

  @override
  Future<TasteLettersSnapshot> load() async {
    final userId = _userId;
    // Both reads go out together. Each change carries the saved card of its
    // record; a deleted record is hidden by its row policy and has none.
    final (letterRows, changeRows) = await (
      _client
          .from('taste_letters')
          .select('axes,record_count,updated_at')
          .eq('user_id', userId)
          .limit(1),
      _client
          .from('taste_letter_changes')
          .select(
            'axis,from_letter,to_letter,left_share,right_share,'
            'product_name,changed_at,drink_records(taste_cards(id))',
          )
          .eq('user_id', userId)
          .order('changed_at', ascending: true),
    ).wait;
    if (_userId != userId) throw StateError('the signed-in account changed');
    unawaited(
      saved?.write(_savedName, <String, Object?>{
        'letters': letterRows,
        'changes': changeRows,
      }),
    );
    return _snapshot(letterRows, changeRows);
  }

  @override
  Future<TasteLettersSnapshot?> kept() async {
    final copy = await saved?.read(_savedName);
    if (copy case {
      'letters': final List letters,
      'changes': final List changes,
    }) {
      return _snapshot(_rows(letters), _rows(changes));
    }
    return null;
  }

  static List<Map<String, dynamic>> _rows(List<Object?> rows) =>
      <Map<String, dynamic>>[
        for (final row in rows) Map<String, dynamic>.from(row! as Map),
      ];

  static TasteLettersSnapshot _snapshot(
    List<Map<String, dynamic>> letterRows,
    List<Map<String, dynamic>> changeRows,
  ) {
    if (letterRows.isEmpty) return const TasteLettersSnapshot();
    return TasteLettersSnapshot(
      state: TasteLettersState.fromRow(letterRows.first),
      changes: [
        for (final row in changeRows)
          ?TasteLetterChange.fromRow(row, resultId: _cardIdOf(row)),
      ],
    );
  }

  static String? _cardIdOf(Map<String, dynamic> change) {
    final record = change['drink_records'];
    final card = record is Map ? record['taste_cards'] : null;
    // One card per record; the embed is an object, or a list of one.
    final first = card is List ? card.firstOrNull : card;
    return first is Map ? first['id'] as String? : null;
  }
}
