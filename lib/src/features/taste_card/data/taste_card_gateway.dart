import '../../../core/errors/connection_failure.dart';
import 'taste_card_result.dart';
import 'taste_card_wire_requests.dart';

enum TasteCardGatewayOperation {
  create,
  convert,
  detail,
  delete,
  answers,
  revise,
}

class TasteCardGatewayException implements Exception, RewordedFailure {
  const TasteCardGatewayException(this.operation, {this.code, this.cause});

  final TasteCardGatewayOperation operation;
  final String? code;

  /// What the call failed with, when it was not a refusal with a [code].
  @override
  final Object? cause;

  @override
  String toString() =>
      'TasteCardGatewayException(${operation.name}, ${code ?? 'no code'})';
}

/// A card source that can also give back the copy the phone kept of a card
/// it loaded before; `null` when there is none.
abstract interface class KeepsCards {
  Future<TasteCardResult?> keptResult(String resultId);
}

abstract interface class TasteCardGateway {
  bool get isAuthenticated;

  Future<TasteCardCreateOutcome> create(CreateTasteCardResultRequest request);

  Future<TasteCardResult> convert(AnonymousTasteCardConversionRequest request);

  Future<TasteCardResult> fetchOwnedResult(String resultId);

  /// Deletes the record behind the account's saved card [resultId]; the
  /// server recomputes the account's 네 글자 without it.
  Future<void> deleteOwnedResult(String resultId);
}
