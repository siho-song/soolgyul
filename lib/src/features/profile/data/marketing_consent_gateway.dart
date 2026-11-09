import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/signed_in.dart';

abstract interface class MarketingConsentGateway {
  Future<bool> load();
  Future<bool> save(bool accepted);
}

class SupabaseMarketingConsentGateway implements MarketingConsentGateway {
  SupabaseMarketingConsentGateway(this._client);
  final SupabaseClient _client;

  Future<bool> _call(String name, [Map<String, dynamic>? params]) async {
    final userId = signedInUserId(_client);
    final result = await _client.rpc(name, params: params);
    if (_client.auth.currentUser?.id != userId || result is! bool) {
      throw StateError('수신 동의 상태를 확인하지 못했습니다.');
    }
    return result;
  }

  @override
  Future<bool> load() => _call('soolgyul_get_marketing_consent');
  @override
  Future<bool> save(bool accepted) =>
      _call('soolgyul_set_marketing_consent', {'p_accepted': accepted});
}
