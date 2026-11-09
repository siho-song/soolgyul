import 'package:supabase_flutter/supabase_flutter.dart';

import '../../taste_card/data/taste_card_snapshot_view_data.dart'
    show TasteCardTagKind;
import 'preference_history_content.dart';

class SupabasePreferenceHistoryGateway implements PreferenceHistoryGateway {
  const SupabasePreferenceHistoryGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('로그인이 필요합니다.');
    final from = DateTime(month.year, month.month);
    final to = DateTime(month.year, month.month + 1);
    final rows = await _client.rpc(
      'soolgyul_my_drink_history',
      params: <String, Object?>{
        'p_from': from.toUtc().toIso8601String(),
        'p_to': to.toUtc().toIso8601String(),
      },
    );
    if (rows is! List) throw StateError('기록 목록 형식이 아닙니다.');
    final images = await _imagesOf(<String>{
      for (final row in rows)
        if (row is Map && row['alcohol_item_id'] is String)
          row['alcohol_item_id'] as String,
    });
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('로그인 계정이 변경되었습니다.');
    }
    return <HistoryRecord>[
      for (final row in rows) _parse(row as Map<String, dynamic>, images),
    ];
  }

  @override
  Future<DateTime?> latestRecordedAt() async {
    if (_client.auth.currentUser == null) throw StateError('로그인이 필요합니다.');
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

  /// Public representative photos of the bottles, by catalog item id.
  Future<Map<String, String>> _imagesOf(Set<String> itemIds) async {
    if (itemIds.isEmpty) return const <String, String>{};
    final rows = await _client
        .rpc('soolgyul_catalog_primary_media_rows_v1')
        .inFilter('alcohol_item_id', itemIds.toList())
        .select('alcohol_item_id,media_path');
    return <String, String>{
      for (final row in rows)
        if (row['media_path'] case final String path when path.isNotEmpty)
          row['alcohol_item_id'] as String: _client.storage
              .from('alcohol-product-images')
              .getPublicUrl(path),
    };
  }

  HistoryRecord _parse(Map<String, dynamic> row, Map<String, String> images) {
    final note = (row['note'] as String?)?.trim();
    // The brief is the card's line without its dressing; a card made before
    // it was written lends its long line, which draws **word** in bold.
    final brief = (row['brief'] as String?)?.trim();
    final summary = brief != null && brief.isNotEmpty
        ? brief
        : (row['summary'] as String?)?.replaceAll('**', '').trim();
    return HistoryRecord(
      resultId: row['result_id'] as String,
      title: row['name'] as String,
      categoryKey: row['category_key'] as String?,
      categoryLabel: row['category_label'] as String? ?? '기타',
      recordedAt: DateTime.parse(row['recorded_at'] as String).toLocal(),
      tags: <HistoryTag>[
        for (final tag in row['tags'] as List? ?? const <Object?>[])
          if (tag case {'label': final String label} when label.isNotEmpty)
            HistoryTag(label, _tagKind(tag['kind'])),
      ],
      summary: summary == null || summary.isEmpty ? null : summary,
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
