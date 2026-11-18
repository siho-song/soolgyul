import 'package:supabase_flutter/supabase_flutter.dart';

import 'record_note_gateway.dart';

/// The note is kept with the record's tasting note. The owner reads it
/// through the row policy and changes it through the tasting note's one
/// owner RPC, which changes only the fields it is sent.
class SupabaseRecordNoteGateway implements RecordNoteGateway {
  const SupabaseRecordNoteGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<String> loadNote(String recordId) async {
    if (_client.auth.currentUser == null) {
      throw const RecordNoteException('로그인 후 다시 시도해 주세요.');
    }
    try {
      // A record nothing was entered on has no row.
      final row = await _client
          .from('tasting_notes')
          .select('one_line_note')
          .eq('drink_record_id', recordId)
          .maybeSingle();
      return (row?['one_line_note'] as String?) ?? '';
    } on PostgrestException {
      throw const RecordNoteException('총평을 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Future<void> saveNote({
    required String recordId,
    required String note,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const RecordNoteException('로그인 후 다시 시도해 주세요.');
    }
    try {
      await _client.rpc(
        'soolgyul_save_my_tasting_note',
        params: <String, Object?>{
          'p_record_id': recordId,
          // A blank memo clears it.
          'p_note': <String, Object?>{'memo': note},
        },
      );
    } on PostgrestException {
      throw const RecordNoteException('총평을 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
