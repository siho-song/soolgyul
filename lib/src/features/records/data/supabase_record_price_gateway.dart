import 'package:supabase_flutter/supabase_flutter.dart';

import 'record_price.dart';

/// The price is kept with the record's tasting note. The owner reads it
/// through the row policy and changes it through the note's one owner RPC,
/// which changes only the fields it is sent.
class SupabaseRecordPriceGateway implements RecordPriceGateway {
  const SupabaseRecordPriceGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<RecordPrice?> loadPrice(String recordId) async {
    if (_client.auth.currentUser == null) {
      throw const RecordPriceException('로그인 후 다시 시도해 주세요.');
    }
    try {
      // A record nothing was entered on has no row.
      final row = await _client
          .from('tasting_notes')
          .select('purchase_price_won, purchase_price_unit, purchase_place')
          .eq('drink_record_id', recordId)
          .maybeSingle();
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
    if (_client.auth.currentUser == null) {
      throw const RecordPriceException('로그인 후 다시 시도해 주세요.');
    }
    try {
      await _client.rpc(
        'soolgyul_save_my_tasting_note',
        params: <String, Object?>{
          'p_record_id': recordId,
          // The amount and its unit go together; no price clears all three.
          'p_note': <String, Object?>{
            'price_won': price?.amount,
            'price_unit': price?.unit.name,
            'purchase_place': price?.place?.key,
          },
        },
      );
    } on PostgrestException {
      throw const RecordPriceException('구매 정보를 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
