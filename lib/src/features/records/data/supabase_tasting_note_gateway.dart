import 'package:supabase_flutter/supabase_flutter.dart';

import 'tasting_note_gateway.dart';

/// The owner reads the note through the row policy and changes it through
/// the one owner RPC, which changes only the fields it is sent.
class SupabaseTastingNoteGateway implements TastingNoteGateway {
  const SupabaseTastingNoteGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<Map<String, String>> load(String recordId) async {
    if (_client.auth.currentUser == null) {
      throw const TastingNoteException('로그인 후 다시 시도해 주세요.');
    }
    try {
      // A record nothing was entered on has no row.
      final row = await _client
          .from('tasting_notes')
          .select(TastingNoteField.all.join(', '))
          .eq('drink_record_id', recordId)
          .maybeSingle();
      return <String, String>{
        for (final field in TastingNoteField.all) field: ?_entry(row?[field]),
      };
    } on PostgrestException {
      throw const TastingNoteException('테이스팅 노트를 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  /// A stored field as the app holds it: null for nothing entered. The
  /// ways it was drunk are stored as a list.
  static String? _entry(Object? stored) => switch (stored) {
    final String value when value.trim().isNotEmpty => value.trim(),
    final List<Object?> values when values.isNotEmpty =>
      values.whereType<String>().join(TastingNoteField.servingSeparator),
    _ => null,
  };

  @override
  Future<void> save(String recordId, Map<String, Object?> patch) async {
    if (_client.auth.currentUser == null) {
      throw const TastingNoteException('로그인 후 다시 시도해 주세요.');
    }
    try {
      await _client.rpc(
        'soolgyul_save_my_tasting_note',
        params: <String, Object?>{
          'p_record_id': recordId,
          'p_note': <String, Object?>{
            ...patch,
            if (patch[TastingNoteField.serving] case final String ways)
              TastingNoteField.serving: ways.split(
                TastingNoteField.servingSeparator,
              ),
          },
        },
      );
    } on PostgrestException {
      throw const TastingNoteException('테이스팅 노트를 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
