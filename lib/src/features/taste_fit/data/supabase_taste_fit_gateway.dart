import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/server_error_code.dart';

import 'taste_fit_verdict.dart';
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

  /// As many products as the `taste-fit` function takes in one call (its
  /// `TASTE_FIT_MAX_PRODUCTS`); it refuses a longer list.
  static const productsPerCall = 20;

  @override
  Future<TasteFitResponse> judge(List<String> productIds) async {
    if (productIds.length <= productsPerCall) return _judgeOneCall(productIds);
    final answers = await Future.wait(<Future<TasteFitResponse>>[
      for (var at = 0; at < productIds.length; at += productsPerCall)
        _judgeOneCall(
          productIds.skip(at).take(productsPerCall).toList(growable: false),
        ),
    ]);
    return TasteFitResponse(
      hasCards: answers.every((answer) => answer.hasCards),
      verdicts: Map<String, TasteFitVerdict>.unmodifiable(
        <String, TasteFitVerdict>{
          for (final answer in answers) ...answer.verdicts,
        },
      ),
    );
  }

  Future<TasteFitResponse> _judgeOneCall(List<String> productIds) async {
    try {
      final data = await _invoke('taste-fit', <String, dynamic>{
        'product_ids': productIds,
      });
      return TasteFitResponse.fromJson(data);
    } on FunctionException catch (error) {
      throw TasteFitGatewayException(code: serverErrorCode(error));
    } catch (error) {
      throw TasteFitGatewayException(cause: error);
    }
  }
}
