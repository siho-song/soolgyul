import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../taste_card_result.dart';
import 'taste_card_gateway.dart';
import 'taste_card_wire_parser.dart';
import 'taste_card_wire_requests.dart';

class SupabaseTasteCardGateway implements TasteCardGateway {
  const SupabaseTasteCardGateway(this._client);

  final SupabaseClient _client;

  @override
  bool get isAuthenticated => _client.auth.currentUser != null;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequestV1 request,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'taste-card-generations',
        body: request.toJson(),
      );
      return TasteCardWireParser.parseCreateResponse(response.data);
    } on TasteCardWireException {
      rethrow;
    } on FunctionException catch (error) {
      throw TasteCardGatewayException(
        TasteCardGatewayOperation.create,
        code: _publicErrorCode(error.details),
      );
    } catch (_) {
      throw const TasteCardGatewayException(TasteCardGatewayOperation.create);
    }
  }

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequestV1 request,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'taste-card-conversions',
        body: request.toJson(),
      );
      return TasteCardWireParser.parseResult(response.data);
    } on TasteCardWireException {
      rethrow;
    } on FunctionException catch (error) {
      throw TasteCardGatewayException(
        TasteCardGatewayOperation.convert,
        code: _publicErrorCode(error.details),
      );
    } catch (_) {
      throw const TasteCardGatewayException(TasteCardGatewayOperation.convert);
    }
  }

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) async {
    try {
      final response = await _client.functions.invoke(
        'taste-card-results',
        method: HttpMethod.get,
        queryParameters: <String, Object?>{'result_id': resultId},
      );
      return TasteCardWireParser.parseResult(response.data);
    } on TasteCardWireException {
      rethrow;
    } on FunctionException catch (error) {
      throw TasteCardGatewayException(
        TasteCardGatewayOperation.detail,
        code: _publicErrorCode(error.details),
      );
    } catch (_) {
      throw const TasteCardGatewayException(TasteCardGatewayOperation.detail);
    }
  }

  @override
  Future<void> deleteOwnedResult(String resultId) async {
    try {
      await _client.functions.invoke(
        'taste-card-results',
        method: HttpMethod.delete,
        queryParameters: <String, Object?>{'result_id': resultId},
      );
    } on FunctionException catch (error) {
      throw TasteCardGatewayException(
        TasteCardGatewayOperation.delete,
        code: _publicErrorCode(error.details),
      );
    } catch (_) {
      throw const TasteCardGatewayException(TasteCardGatewayOperation.delete);
    }
  }
}

String createUuidV4([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

String? _publicErrorCode(Object? details) {
  if (details is Map && details['error_code'] is String) {
    return details['error_code'] as String;
  }
  return null;
}
