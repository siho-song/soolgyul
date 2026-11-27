import 'package:supabase_flutter/supabase_flutter.dart';

import 'record_price.dart';
import 'supabase_tasting_note_row.dart';

/// The 구매 정보 is kept with the record's tasting note.
class SupabaseRecordPriceGateway implements RecordPriceGateway {
  SupabaseRecordPriceGateway(SupabaseClient client)
    : _row = SupabaseTastingNoteRow(client);
  final SupabaseTastingNoteRow _row;

  @override
  Future<RecordPrice?> loadPrice(String recordId) async {
    if (!_row.signedIn) {
      throw const RecordPriceException('로그인 후 다시 시도해 주세요.');
    }
    try {
      final row = await _row.read(recordId, const [
        'purchase_price_won',
        'purchase_place',
      ]);
      return RecordPrice.fromStored(
        row?['purchase_price_won'],
        row?['purchase_place'],
      );
    } on PostgrestException {
      throw const RecordPriceException('구매 정보를 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Future<void> save({required String recordId, int? amount, String? place}) =>
      // A unit stored by an older app goes with the amount it was for.
      _save(recordId, <String, Object?>{
        'price_won': amount,
        'price_unit': null,
        'purchase_place': place,
      });

  Future<void> _save(String recordId, Map<String, Object?> fields) async {
    if (!_row.signedIn) {
      throw const RecordPriceException('로그인 후 다시 시도해 주세요.');
    }
    try {
      await _row.save(recordId, fields);
    } on PostgrestException {
      throw const RecordPriceException('구매 정보를 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
