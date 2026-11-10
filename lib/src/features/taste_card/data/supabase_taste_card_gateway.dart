import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/saved_views.dart';
import 'taste_card_result.dart';
import 'taste_card_gateway.dart';
import 'taste_card_wire_parser.dart';
import 'taste_card_wire_requests.dart';

class SupabaseTasteCardGateway implements TasteCardGateway, KeepsCards {
  const SupabaseTasteCardGateway(this._client, {this.saved});

  final SupabaseClient _client;

  /// Where opened cards are kept for the next time they are opened; `null`
  /// keeps none.
  final SavedViews? saved;

  /// The cards opened most recently stay on the phone.
  static const _cardsKept = 60;

  static String _savedName(String resultId) => 'card-${resultId.toLowerCase()}';

  @override
  Future<TasteCardResult?> keptResult(String resultId) async {
    final copy = await saved?.read(_savedName(resultId));
    if (copy == null) return null;
    try {
      return TasteCardWireParser.parseResult(copy);
    } catch (_) {
      // A copy from an older card format is no copy.
      return null;
    }
  }

  @override
  bool get isAuthenticated => _client.auth.currentUser != null;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequest request,
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
    AnonymousTasteCardConversionRequest request,
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
      final result = TasteCardWireParser.parseResult(response.data);
      unawaited(
        saved?.write(
          _savedName(resultId),
          response.data,
          keepNewest: _cardsKept,
        ),
      );
      return result;
    } on TasteCardWireException {
      rethrow;
    } on FunctionException catch (error) {
      final code = _publicErrorCode(error.details);
      if (code == 'result_not_found') {
        unawaited(saved?.remove(_savedName(resultId)));
      }
      throw TasteCardGatewayException(
        TasteCardGatewayOperation.detail,
        code: code,
      );
    } catch (_) {
      throw const TasteCardGatewayException(TasteCardGatewayOperation.detail);
    }
  }

  @override
  Future<void> deleteOwnedResult(String resultId) async {
    // Gone from the phone whatever the server says next.
    unawaited(saved?.remove(_savedName(resultId)));
    try {
      await _client.functions.invoke(
        'taste-card-results',
        method: HttpMethod.delete,
        queryParameters: <String, Object?>{'result_id': resultId},
      );
    } on FunctionException catch (error) {
      final code = _publicErrorCode(error.details);
      // The card is already gone: an earlier request deleted it and its
      // answer was lost, or the delete was sent twice. That is what was
      // asked for.
      if (code == 'result_not_found') return;
      throw TasteCardGatewayException(
        TasteCardGatewayOperation.delete,
        code: code,
      );
    } catch (_) {
      throw const TasteCardGatewayException(TasteCardGatewayOperation.delete);
    }
  }
}

String? _publicErrorCode(Object? details) {
  if (details is Map && details['error_code'] is String) {
    return details['error_code'] as String;
  }
  return null;
}
