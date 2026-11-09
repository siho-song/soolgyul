import 'package:supabase_flutter/supabase_flutter.dart';

import 'next_drink_guides.dart';
import '../../../core/supabase/signed_in.dart';

class SupabaseNextDrinkGuidesGateway implements NextDrinkGuidesGateway {
  const SupabaseNextDrinkGuidesGateway(this._client);
  final SupabaseClient _client;
  static const slideCount = 3;

  @override
  Future<List<NextDrinkGuide>> load() async {
    signedInUserId(_client);
    final rows = await _client.rpc(
      'soolgyul_my_recent_card_guides',
      params: {'p_limit': slideCount},
    );
    if (rows is! List) throw StateError('가이드 목록 형식이 아닙니다.');
    return [
      for (final (index, row) in rows.indexed)
        NextDrinkGuide.fromRow(
          row,
          r'$guides'
          '[$index]',
        ),
    ];
  }
}
