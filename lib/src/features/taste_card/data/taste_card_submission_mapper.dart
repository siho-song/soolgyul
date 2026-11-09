import '../../catalog/data/catalog_drink.dart';
import '../../../core/sensory/sensory_meanings.dart';
import '../../../core/sensory/sensory_question_flow.dart';
import 'sensory_submission.dart';
import 'taste_card_wire_requests.dart';

abstract final class TasteCardSubmissionMapper {
  /// Shared submission path for onboarding and subsequent sensory records.
  static CreateTasteCardResultRequest fromSensoryFlow({
    required String idempotencyKey,
    String? anonymousSessionId,
    required DrinkSelection selection,
    required SensoryQuestionFlow flow,
    required SensoryMeaningRegistry registry,
  }) {
    if (selection.displayName.trim().isEmpty) {
      throw StateError('술 이름이 있어야 기록을 저장할 수 있습니다.');
    }
    return CreateTasteCardResultRequest(
      idempotencyKey: idempotencyKey,
      anonymousSessionId: anonymousSessionId,
      questionnaireVersion: SensorySubmission.questionnaireVersionKey,
      alcoholIdentification: AlcoholIdentificationInput.catalogMatch(
        alcoholItemId: selection.catalogId,
        alcoholNameSnapshot: selection.displayName.trim(),
        category: _category(selection.category),
      ),
      answers: SensorySubmission.answers(flow: flow, registry: registry),
      // The note and the photo are added to the record after the card.
      q7FreeText: null,
      photoAssetId: null,
    );
  }
}

String? _category(DrinkCategory category) => switch (category) {
  DrinkCategory.redWine ||
  DrinkCategory.whiteWine ||
  DrinkCategory.sparklingWine => 'wine',
  DrinkCategory.whisky => 'whisky',
  DrinkCategory.sake => 'sake',
  DrinkCategory.koreanTraditional => 'korean_traditional',
  DrinkCategory.other => null,
};
