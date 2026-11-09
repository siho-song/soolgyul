import '../../features/taste_card/taste_card_result.dart';

enum TasteCardFlowPhase { idle, submitting, retryable, finalResult, failure }

class TasteCardFlowState {
  TasteCardFlowPhase phase = TasteCardFlowPhase.idle;
  String? idempotencyKey;
  String? anonymousSessionId;
  TasteCardResult? result;

  bool get isBusy => phase == TasteCardFlowPhase.submitting;

  bool beginSubmission({
    required String Function() createId,
    required bool isAuthenticated,
  }) {
    if (isBusy) {
      return false;
    }
    idempotencyKey ??= createId();
    if (!isAuthenticated) {
      anonymousSessionId ??= createId();
    }
    phase = TasteCardFlowPhase.submitting;
    return true;
  }

  void markRetryable() {
    phase = TasteCardFlowPhase.retryable;
  }

  void markFinal(TasteCardResult value) {
    result = value;
    phase = TasteCardFlowPhase.finalResult;
  }

  void markFailure() {
    phase = TasteCardFlowPhase.failure;
  }

  void startNewSubmission() {
    phase = TasteCardFlowPhase.idle;
    idempotencyKey = null;
    anonymousSessionId = null;
    result = null;
  }
}
