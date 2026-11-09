import 'package:flutter/foundation.dart';

import 'taste_card_snapshot_view_data.dart';

enum TasteCardOwnership { anonymous, saved }

enum TasteCardRetryError { catalogUnavailable, engineTemporarilyUnavailable }

@immutable
class TasteCardPendingConversion {
  const TasteCardPendingConversion({
    required this.anonymousSessionId,
    required this.resultId,
    required this.snapshotRef,
    required this.conversionToken,
  });

  final String anonymousSessionId;
  final String resultId;
  final String snapshotRef;
  final String conversionToken;
}

@immutable
class TasteCardResult {
  const TasteCardResult({
    required this.resultId,
    required this.snapshotRef,
    required this.ownership,
    required this.viewData,
    this.recordId,
    this.pendingConversion,
  });

  final String resultId;

  /// The drink record behind the card; liked cards are keyed by it.
  final String? recordId;
  final String snapshotRef;
  final TasteCardOwnership ownership;
  final TasteCardSnapshotViewData viewData;
  final TasteCardPendingConversion? pendingConversion;

  bool get isSaved => ownership == TasteCardOwnership.saved;
}

sealed class TasteCardCreateOutcome {
  const TasteCardCreateOutcome();
}

@immutable
final class TasteCardFinalOutcome extends TasteCardCreateOutcome {
  const TasteCardFinalOutcome(this.result);

  final TasteCardResult result;
}

@immutable
final class TasteCardRetryableOutcome extends TasteCardCreateOutcome {
  const TasteCardRetryableOutcome({
    required this.idempotencyKey,
    required this.attemptRef,
    required this.error,
    required this.retryAfter,
  });

  final String idempotencyKey;
  final String attemptRef;
  final TasteCardRetryError error;
  final Duration? retryAfter;
}
