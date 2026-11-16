import '../../../core/sensory/sensory_meanings.dart';
import '../../../core/sensory/sensory_question_flow.dart';
import 'taste_card_wire_requests.dart';

/// Raw answer keys for the published sensory questionnaire. Interpretation
/// remains on the server: no client-computed meaning, intensity or preference is
/// added to the answer wire format.
abstract final class SensorySubmission {
  static const questionnaireVersionKey = 'sensory-questionnaire-v2';
  static const questionKeys = SensoryQuestionKeys.all;

  /// The questions answered, each with its chosen option keys. 재음용 의사
  /// is always among them; a question left empty is not sent.
  static List<QuestionnaireAnswerInput> answers({
    required SensoryQuestionFlow flow,
    required SensoryMeaningRegistry registry,
  }) {
    if (flow.revisit == null) {
      throw StateError('the revisit answer is missing');
    }
    final grouped = registry.readAnswers(flow);
    return List.unmodifiable([
      for (final key in questionKeys)
        if (grouped[key]!.isNotEmpty)
          QuestionnaireAnswerInput(
            questionKey: key,
            selectedOptionKeys: List.unmodifiable(grouped[key]!),
          ),
    ]);
  }
}
