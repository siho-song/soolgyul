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

  /// The account's records made from [from] up to [to], oldest first, as
  /// the server sends them.
  Future<List<Object?>> _rows(DateTime from, DateTime to) async {
    final rows = await askAsSignedIn<dynamic>(
      _client,
      (_) => _client.rpc(
        'soolgyul_my_drink_history',
        params: <String, Object?>{
          'p_from': from.toUtc().toIso8601String(),
          'p_to': to.toUtc().toIso8601String(),
        },
      ),
    );
    if (rows is! List) throw StateError('the records are not a list');
    return rows;
  }

  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async {
    final rows = await _rows(
      DateTime(month.year, month.month),
      DateTime(month.year, month.month + 1),
    );
    final records = _records(rows);
    unawaited(saved?.write(_monthName(month), rows, keepNewest: _monthsKept));
    return records;
  }

  /// The server answers no span wider than 45 days, and nothing at all for
  /// one that is.
  static const _widestSpan = Duration(days: 45);

  @override
  Future<List<HistoryRecord>> loadAll() async {
    signedInUserId(_client);
    // The oldest record says how far back to ask; the same row policies and
    // card join as [latestRecordedAt].
    final oldest = await _client
        .from('drink_records')
        .select('created_at, taste_cards!inner(id)')
        .order('created_at', ascending: true)
        .limit(1);
    if (oldest.isEmpty) return const <HistoryRecord>[];
    final first = DateTime.parse(oldest.first['created_at'] as String).toUtc();
    final end = DateTime.now().toUtc().add(const Duration(days: 1));
    // One call per span from the oldest record's day to now, all at once.
    final spans = await Future.wait(<Future<List<Object?>>>[
      for (
        var from = DateTime.utc(first.year, first.month, first.day);
        from.isBefore(end);
        from = from.add(_widestSpan)
      )
        _rows(from, from.add(_widestSpan)),
    ]);
    return <HistoryRecord>[
      for (final rows in spans.reversed) ..._records(rows).reversed,
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
            HistoryTag(
              label,
              TasteCardTagKind.fromKey(tag['kind']) ?? TasteCardTagKind.fine,
            ),
      ],
      summary: tasteCardOneLine(
        brief: row['brief'] as String?,
        summary: row['summary'] as String?,
      ),
      note: note == null || note.isEmpty ? null : note,
      price: RecordPrice.fromStored(row['price_won'], row['purchase_place']),
      imageUrl: catalogPhotoUrl(_client, row['media_path']),
    );
  }
}
