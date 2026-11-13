import 'package:supabase_flutter/supabase_flutter.dart';

import 'record_price.dart';

/// The owner reads the price through the row policy and changes it through
/// the one owner RPC that changes nothing else.
class SupabaseRecordPriceGateway implements RecordPriceGateway {
  const SupabaseRecordPriceGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<RecordPrice?> loadPrice(String recordId) async {
    if (_client.auth.currentUser == null) {
      throw const RecordPriceException('로그인 후 다시 시도해 주세요.');
    }
    try {
      final row = await _client
          .from('drink_records')
          .select('purchase_price_won, purchase_price_unit')
          .eq('id', recordId)
          .maybeSingle();
      return RecordPrice.fromStored(
        row?['purchase_price_won'],
        row?['purchase_price_unit'],
      );
    } on PostgrestException {
      throw const RecordPriceException('구입 가격을 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Future<void> savePrice({required String recordId, RecordPrice? price}) async {
    if (_client.auth.currentUser == null) {
      throw const RecordPriceException('로그인 후 다시 시도해 주세요.');
    }
    try {
      await _client.rpc(
        'soolgyul_update_my_drink_record_price',
        params: <String, Object?>{
          'p_record_id': recordId,
          'p_amount': price?.amount,
          'p_unit': price?.unit.name,
        },
      );
    } on PostgrestException {
      throw const RecordPriceException('구입 가격을 저장하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
