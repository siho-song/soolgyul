import 'package:supabase_flutter/supabase_flutter.dart';

import '../taste_fit_verdict.dart';
import 'taste_fit_gateway.dart';

typedef TasteFitFunctionInvoker =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);

class SupabaseTasteFitGateway implements TasteFitGateway {
  SupabaseTasteFitGateway(
    SupabaseClient client, {
    TasteFitFunctionInvoker? functionInvoker,
  }) : _invoke =
           functionInvoker ??
           ((functionName, body) async {
             final response = await client.functions.invoke(
               functionName,
               body: body,
             );
             return response.data;
           });

  final TasteFitFunctionInvoker _invoke;

  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    try {
      final data = await _invoke('taste-fit', <String, dynamic>{
        'product_ids': productIds,
      });
      return TasteFitResponse.fromJson(data);
    } on FunctionException catch (error) {
      throw TasteFitGatewayException(code: _publicErrorCode(error.details));
    } catch (_) {
      throw const TasteFitGatewayException();
    }
  }
}

String? _publicErrorCode(Object? details) {
  if (details is Map && details['error_code'] is String) {
    return details['error_code'] as String;
  }
  return null;
}
