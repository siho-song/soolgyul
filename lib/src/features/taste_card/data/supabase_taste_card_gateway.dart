import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/server_error_code.dart';

import '../../../core/saved_views.dart';
import 'taste_card_answers_gateway.dart';
import 'taste_card_result.dart';
import 'taste_card_gateway.dart';
import 'taste_card_wire_parser.dart';
import 'taste_card_wire_requests.dart';

class SupabaseTasteCardGateway
    implements TasteCardGateway, KeepsCards, TasteCardAnswersGateway {
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

  /// Asks a card function and reads its answer. A refusal, a failed call
  /// and an answer that is no answer all become a
  /// [TasteCardGatewayException] of [operation], with the function's error
  /// code when it gave one; an answer in a card format this app does not
  /// know stays a [TasteCardWireException].
  Future<T> _ask<T>(
    TasteCardGatewayOperation operation,
    Future<FunctionResponse> Function() ask,
    T Function(dynamic data) read,
  ) async {
    try {
      return read((await ask()).data);
    } on TasteCardWireException {
      rethrow;
    } on FunctionException catch (error) {
      throw TasteCardGatewayException(operation, code: serverErrorCode(error));
    } catch (_) {
      throw TasteCardGatewayException(operation);
    }
  }

  /// Keeps the answer the card was read from, for the next time it is opened.
  void _keep(String resultId, dynamic data) => unawaited(
    saved?.write(_savedName(resultId), data, keepNewest: _cardsKept),
  );

  @override
  Future<TasteCardCreateOutcome> create(CreateTasteCardResultRequest request) =>
      _ask(
        TasteCardGatewayOperation.create,
        () => _client.functions.invoke(
          'taste-card-generations',
          body: request.toJson(),
        ),
        TasteCardWireParser.parseCreateResponse,
      );

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequest request,
  ) => _ask(
    TasteCardGatewayOperation.convert,
    () => _client.functions.invoke(
      'taste-card-conversions',
      body: request.toJson(),
    ),
    TasteCardWireParser.parseResult,
  );

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) async {
    try {
      return await _ask(
        TasteCardGatewayOperation.detail,
        () => _client.functions.invoke(
          'taste-card-results',
          method: HttpMethod.get,
          queryParameters: <String, Object?>{'result_id': resultId},
        ),
        (data) {
          final result = TasteCardWireParser.parseResult(data);
          _keep(resultId, data);
          return result;
        },
      );
    } on TasteCardGatewayException catch (error) {
      if (error.code == 'result_not_found') {
        unawaited(saved?.remove(_savedName(resultId)));
      }
      rethrow;
    }
  }

  @override
  Future<TasteCardAnswers> loadAnswers(String resultId) => _ask(
    TasteCardGatewayOperation.answers,
    () => _client.functions.invoke(
      'taste-card-results',
      method: HttpMethod.get,
      queryParameters: <String, Object?>{
        'result_id': resultId,
        'part': 'answers',
      },
    ),
    TasteCardWireParser.parseAnswers,
  );

  @override
  Future<TasteCardResult> reviseAnswers(
    String resultId,
    Map<String, List<String>> answers,
  ) => _ask(
    TasteCardGatewayOperation.revise,
    () => _client.functions.invoke(
      'taste-card-results',
      method: HttpMethod.patch,
      queryParameters: <String, Object?>{'result_id': resultId},
      body: <String, Object?>{
        'answers': <Map<String, Object?>>[
          for (final MapEntry(:key, :value) in answers.entries)
            QuestionnaireAnswerInput(
              questionKey: key,
              selectedOptionKeys: value,
            ).toJson(),
        ],
      },
    ),
    (data) {
      final result = TasteCardWireParser.parseResult(data);
      // The copy the phone kept is of the card before it was written again.
      _keep(resultId, data);
      return result;
    },
  );

  @override
  Future<void> deleteOwnedResult(String resultId) async {
    // Gone from the phone whatever the server says next.
    unawaited(saved?.remove(_savedName(resultId)));
    try {
      await _ask(
        TasteCardGatewayOperation.delete,
        () => _client.functions.invoke(
          'taste-card-results',
          method: HttpMethod.delete,
          queryParameters: <String, Object?>{'result_id': resultId},
        ),
        (_) {},
      );
    } on TasteCardGatewayException catch (error) {
      // The card is already gone: an earlier request deleted it and its
      // answer was lost, or the delete was sent twice. That is what was
      // asked for.
      if (error.code != 'result_not_found') rethrow;
    }
  }
}
