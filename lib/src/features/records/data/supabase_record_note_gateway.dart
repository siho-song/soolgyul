import 'package:supabase_flutter/supabase_flutter.dart';

import 'record_note_gateway.dart';

/// Records are written by service RPCs only; the one owner RPC here changes
/// nothing but the note. The owner reads the note through the row policy.
class SupabaseRecordNoteGateway implements RecordNoteGateway {
  const SupabaseRecordNoteGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<String> loadNote(String recordId) async {
    if (_client.auth.currentUser == null) {
      throw const RecordNoteException('로그인 후 다시 시도해 주세요.');
    }
    try {
      final row = await _client
          .from('drink_records')
          .select('one_line_note')
          .eq('id', recordId)
          .maybeSingle();
      return (row?['one_line_note'] as String?) ?? '';
    } on PostgrestException {
      throw const RecordNoteException('메모를 불러오지 못했어요. 다시 시도해 주세요.');
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
        'soolgyul_update_my_drink_record_note',
        params: {'p_record_id': recordId, 'p_note': note},
      );
    } on PostgrestException {
      throw const RecordNoteException('메모를 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
