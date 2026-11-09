/// Request bodies sent to the taste card Edge Functions.
library;

/// Thrown when a request or a server response breaks the wire contract.
class TasteCardWireException implements Exception {
  const TasteCardWireException(this.code, this.path);

  final String code;
  final String path;

  @override
  String toString() => 'TasteCardWireException($code at $path)';
}

class QuestionnaireAnswerInput {
  const QuestionnaireAnswerInput({
    required this.questionKey,
    required this.selectedOptionKeys,
    this.freeText,
  });

  final String questionKey;
  final List<String> selectedOptionKeys;
  final String? freeText;

  Map<String, Object?> toJson() => <String, Object?>{
    'question_key': questionKey,
    'selected_option_keys': selectedOptionKeys,
    'free_text': freeText,
  };
}

/// Every record points at one catalog item.
class AlcoholIdentificationInput {
  const AlcoholIdentificationInput.catalogMatch({
    required this.alcoholItemId,
    required this.alcoholNameSnapshot,
    this.category,
  });

  final String alcoholItemId;
  final String alcoholNameSnapshot;
  final String? category;

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': 'catalog_match',
    'alcohol_item_id': alcoholItemId,
    'alcohol_name_snapshot': alcoholNameSnapshot,
    'category': category,
  };
}

class CreateTasteCardResultRequest {
  const CreateTasteCardResultRequest({
    required this.idempotencyKey,
    required this.questionnaireVersion,
    required this.alcoholIdentification,
    required this.answers,
    this.anonymousSessionId,
    this.q7FreeText,
    this.photoAssetId,
  });

  final String idempotencyKey;
  final String? anonymousSessionId;
  final String questionnaireVersion;
  final AlcoholIdentificationInput alcoholIdentification;
  final List<QuestionnaireAnswerInput> answers;
  final String? q7FreeText;
  final String? photoAssetId;

  Map<String, Object?> toJson() => <String, Object?>{
    'idempotency_key': idempotencyKey,
    'anonymous_session_id': anonymousSessionId,
    'questionnaire_version': questionnaireVersion,
    'alcohol_identification': alcoholIdentification.toJson(),
    'answers': <Map<String, Object?>>[
      for (final answer in answers) answer.toJson(),
    ],
    'q7_free_text': q7FreeText,
    'photo_asset_id': photoAssetId,
  };
}

class AnonymousTasteCardConversionRequest {
  const AnonymousTasteCardConversionRequest({
    required this.anonymousSessionId,
    required this.resultId,
    required this.conversionToken,
    required this.idempotencyKey,
  });

  final String anonymousSessionId;
  final String resultId;
  final String conversionToken;
  final String idempotencyKey;

  Map<String, Object?> toJson() => <String, Object?>{
    'anonymous_session_id': anonymousSessionId,
    'result_id': resultId,
    'conversion_token': conversionToken,
    'idempotency_key': idempotencyKey,
  };
}
