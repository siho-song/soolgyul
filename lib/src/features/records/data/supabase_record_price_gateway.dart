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
        'purchase_price_unit',
        'purchase_place',
      ]);
      return RecordPrice.fromStored(
        row?['purchase_price_won'],
        row?['purchase_price_unit'],
        row?['purchase_place'],
      );
    } on PostgrestException {
      throw const RecordPriceException('구매 정보를 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Future<void> savePrice({required String recordId, RecordPrice? price}) async {
    if (!_row.signedIn) {
      throw const RecordPriceException('로그인 후 다시 시도해 주세요.');
    }
    try {
      // The amount and its unit go together; no price clears all three.
      await _row.save(recordId, <String, Object?>{
        'price_won': price?.amount,
        'price_unit': price?.unit.name,
        'purchase_place': price?.place?.key,
      });
    } on PostgrestException {
      throw const RecordPriceException('구매 정보를 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
