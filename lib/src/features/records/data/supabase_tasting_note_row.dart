import 'package:supabase_flutter/supabase_flutter.dart';

/// A record's row of what its owner added after recording: the 테이스팅 노트
/// fields, the 총평 and the 구매 정보 are columns of one row. The owner reads
/// it through the row policy and changes it through the one owner RPC, which
/// changes only the fields it is sent.
class SupabaseTastingNoteRow {
  const SupabaseTastingNoteRow(this._client);
  final SupabaseClient _client;

  bool get signedIn => _client.auth.currentUser != null;

  /// The given columns of the record's row; null for a record nothing was
  /// entered on, which has no row.
  Future<Map<String, dynamic>?> read(
    String recordId,
    Iterable<String> columns,
  ) => _client
      .from('tasting_notes')
      .select(columns.join(', '))
      .eq('drink_record_id', recordId)
      .maybeSingle();

  /// Stores the fields named in [fields] and leaves the others as they are;
  /// a null value clears its field.
  Future<void> save(String recordId, Map<String, Object?> fields) =>
      _client.rpc(
        'soolgyul_save_my_tasting_note',
        params: <String, Object?>{'p_record_id': recordId, 'p_note': fields},
      );
}
