import 'package:supabase_flutter/supabase_flutter.dart';

import '../../taste_card/data/taste_card_one_line.dart';
import '../../taste_card/data/taste_card_snapshot_view_data.dart'
    show TasteCardTagKind;
import 'preference_history_content.dart';
import '../../../core/supabase/signed_in.dart';
import '../../catalog/data/catalog_photos.dart';

class SupabasePreferenceHistoryGateway implements PreferenceHistoryGateway {
  const SupabasePreferenceHistoryGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async {
    final userId = signedInUserId(_client);
    final from = DateTime(month.year, month.month);
    final to = DateTime(month.year, month.month + 1);
    final rows = await _client.rpc(
      'soolgyul_my_drink_history',
      params: <String, Object?>{
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      },
    );
    if (rows is! List) throw StateError('the records are not a list');
    final images = await catalogPhotoUrls(_client, <String>{
      for (final row in rows)
        if (row is Map && row['alcohol_item_id'] is String)
          row['alcohol_item_id'] as String,
    });
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('the signed-in account changed');
    }
    return <HistoryRecord>[
      for (final row in rows) _parse(row as Map<String, dynamic>, images),
    ];
  }

  @override
  Future<DateTime?> latestRecordedAt() async {
    signedInUserId(_client);
    // Row policies limit this to the owner's live records; the card join
    // skips a record whose card never came.
    final rows = await _client
        .from('drink_records')
        .select('created_at, taste_cards!inner(id)')
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['created_at'] as String).toLocal();
  }

  HistoryRecord _parse(Map<String, dynamic> row, Map<String, String> images) {
    final note = (row['note'] as String?)?.trim();
    return HistoryRecord(
      resultId: row['result_id'] as String,
      title: row['name'] as String,
      categoryKey: row['category_key'] as String?,
      categoryLabel: row['category_label'] as String? ?? '기타 주류',
      recordedAt: DateTime.parse(row['recorded_at'] as String).toLocal(),
      tags: <HistoryTag>[
        for (final tag in row['tags'] as List? ?? const <Object?>[])
          if (tag case {'label': final String label} when label.isNotEmpty)
            HistoryTag(label, _tagKind(tag['kind'])),
      ],
      summary: tasteCardOneLine(
        brief: row['brief'] as String?,
        summary: row['summary'] as String?,
      ),
      note: note == null || note.isEmpty ? null : note,
      imageUrl: images[row['alcohol_item_id']],
    );
  }
}

TasteCardTagKind _tagKind(Object? kind) => switch (kind) {
  'liked' => TasteCardTagKind.liked,
  'less' => TasteCardTagKind.less,
  'burden' => TasteCardTagKind.burden,
  'more' => TasteCardTagKind.more,
  _ => TasteCardTagKind.fine,
};
