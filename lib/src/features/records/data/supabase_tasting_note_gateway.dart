import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_tasting_note_row.dart';
import 'tasting_note_gateway.dart';

class SupabaseTastingNoteGateway implements TastingNoteGateway {
  SupabaseTastingNoteGateway(SupabaseClient client)
    : _row = SupabaseTastingNoteRow(client);
  final SupabaseTastingNoteRow _row;

  @override
  Future<Map<String, String>> load(String recordId) async {
    if (!_row.signedIn) {
      throw const TastingNoteException('로그인 후 다시 시도해 주세요.');
    }
    try {
      final row = await _row.read(recordId, TastingNoteField.all);
      return <String, String>{
        for (final field in TastingNoteField.all) field: ?_entry(row?[field]),
      };
    } on PostgrestException {
      throw const TastingNoteException('테이스팅 노트를 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  /// A stored field as the app holds it: null for nothing entered. The
  /// ways it was drunk are stored as a list, the stars as a number.
  static String? _entry(Object? stored) => switch (stored) {
    final String value when value.trim().isNotEmpty => value.trim(),
    // 4.0 reads as 4, a half star as 4.5.
    final num value => value % 1 == 0 ? '${value.toInt()}' : '$value',
    final List<Object?> values when values.isNotEmpty =>
      values.whereType<String>().join(TastingNoteField.servingSeparator),
    _ => null,
  };

  @override
  Future<void> save(String recordId, Map<String, Object?> patch) async {
    if (!_row.signedIn) {
      throw const TastingNoteException('로그인 후 다시 시도해 주세요.');
    }
    try {
      await _row.save(recordId, <String, Object?>{
        ...patch,
        // The stars are a number on the server.
        if (patch[TastingNoteField.rating] case final String stars)
          TastingNoteField.rating: num.parse(stars),
        if (patch[TastingNoteField.serving] case final String ways)
          TastingNoteField.serving: ways.split(
            TastingNoteField.servingSeparator,
          ),
      });
    } on PostgrestException {
      throw const TastingNoteException('테이스팅 노트를 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
