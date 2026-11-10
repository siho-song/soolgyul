import '../../../core/sensory/sensory_meanings.dart';
import '../../../core/sensory/sensory_question_flow.dart';
import 'taste_card_wire_requests.dart';

/// Raw answer keys for the published sensory questionnaire. Interpretation
/// remains on the server: no client-computed meaning, intensity or preference is
/// added to the answer wire format.
abstract final class SensorySubmission {
  static const questionnaireVersionKey = 'sensory-questionnaire-v1';
  static const questionKeys = [
    'sensory_revisit',
    'sensory_aroma',
    'sensory_taste',
    'sensory_mouthfeel',
    'sensory_finish',
  ];

  static List<QuestionnaireAnswerInput> answers({
    required SensoryQuestionFlow flow,
    required SensoryMeaningRegistry registry,
  }) {
    if (flow.revisit == null) {
      throw StateError('the revisit answer is missing');
    }
    final grouped = <String, List<SensoryMeaning>>{
      for (final key in questionKeys) key: [],
    };
    for (final answer in registry.readAnswers(flow)) {
      final section = answer.section?.name ?? answer.id.split(':').first;
      final key = 'sensory_$section';
      final group = grouped[key];
      if (group == null) {
        throw StateError('Unsupported sensory question: $key');
      }
      group.add(answer);
    }
    return List.unmodifiable([
      for (final key in questionKeys)
        if (grouped[key]!.isNotEmpty) _answer(key, grouped[key]!),
    ]);
  }

  static QuestionnaireAnswerInput _answer(
    String key,
    List<SensoryMeaning> values,
  ) {
    // Preserve the existing request limit; never truncate selected answers.
    if (values.length > 20) {
      throw StateError('Too many sensory answers for $key');
    }
    return QuestionnaireAnswerInput(
      questionKey: key,
      selectedOptionKeys: List.unmodifiable(values.map((value) => value.id)),
    );
  }
}
