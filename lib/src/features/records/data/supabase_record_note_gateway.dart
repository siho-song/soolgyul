import 'package:supabase_flutter/supabase_flutter.dart';

import 'record_note_gateway.dart';
import 'supabase_tasting_note_row.dart';

/// The 총평 is kept with the record's tasting note.
class SupabaseRecordNoteGateway implements RecordNoteGateway {
  SupabaseRecordNoteGateway(SupabaseClient client)
    : _row = SupabaseTastingNoteRow(client);
  final SupabaseTastingNoteRow _row;

  @override
  Future<String> loadNote(String recordId) async {
    if (!_row.signedIn) {
      throw const RecordNoteException('로그인 후 다시 시도해 주세요.');
    }
    try {
      final row = await _row.read(recordId, const ['one_line_note']);
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
    if (!_row.signedIn) {
      throw const RecordNoteException('로그인 후 다시 시도해 주세요.');
    }
    try {
      // A blank memo clears it.
      await _row.save(recordId, <String, Object?>{'memo': note});
    } on PostgrestException {
      throw const RecordNoteException('총평을 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
