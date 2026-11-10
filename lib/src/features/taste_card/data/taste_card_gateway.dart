import 'taste_card_result.dart';
import 'taste_card_wire_requests.dart';

enum TasteCardGatewayOperation { create, convert, detail, delete }

class TasteCardGatewayException implements Exception {
  const TasteCardGatewayException(this.operation, {this.code});

  final TasteCardGatewayOperation operation;
  final String? code;
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
