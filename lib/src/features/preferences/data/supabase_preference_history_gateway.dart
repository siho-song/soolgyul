import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/saved_views.dart';

import '../../taste_card/data/taste_card_one_line.dart';
import '../../taste_card/data/taste_card_snapshot_view_data.dart'
    show TasteCardTagKind;
import 'preference_history_content.dart';
import '../../records/data/record_price.dart';
import '../../../core/supabase/signed_in.dart';
import '../../catalog/data/catalog_photos.dart';

class SupabasePreferenceHistoryGateway
    implements PreferenceHistoryGateway, KeepsHistory {
  const SupabasePreferenceHistoryGateway(this._client, {this.saved});
  final SupabaseClient _client;

  /// Where the last answers are kept for the next launch; `null` keeps none.
  final SavedViews? saved;
  static const _latestName = 'latest';

  /// A year of months stays on the phone.
  static const _monthsKept = 12;

  static String _monthName(DateTime month) =>
      'history-${month.year}-${month.month.toString().padLeft(2, '0')}';

  @override
  Future<List<HistoryRecord>?> keptMonth(DateTime month) async {
    final copy = await saved?.read(_monthName(month));
    return copy is List ? _records(copy) : null;
  }

  @override
  Future<DateTime?> keptLatest() async {
    final copy = await saved?.read(_latestName);
    return copy is Map && copy['at'] is String
        ? DateTime.parse(copy['at'] as String).toLocal()
        : null;
  }

  List<HistoryRecord> _records(List<Object?> rows) => <HistoryRecord>[
    for (final row in rows) _parse(Map<String, dynamic>.from(row! as Map)),
  ];

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
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('the signed-in account changed');
    }
    final records = _records(rows);
    unawaited(saved?.write(_monthName(month), rows, keepNewest: _monthsKept));
    return records;
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
    final at = rows.isEmpty ? null : rows.first['created_at'] as String;
    unawaited(saved?.write(_latestName, <String, Object?>{'at': at}));
    return at == null ? null : DateTime.parse(at).toLocal();
  }

  HistoryRecord _parse(Map<String, dynamic> row) {
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
      price: RecordPrice.fromStored(row['price_won'], row['price_unit']),
      imageUrl: catalogPhotoUrl(_client, row['media_path']),
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
