import 'dart:convert';

import '../../core/sensory/sensory_question_flow.dart';
import '../../features/onboarding/data/sensory_questionnaire_data.dart';

/// Loaded questionnaire data and the in-progress answer flow for one record.
///
/// Onboarding and repeat records each own a session; they never share one.
class SensorySession {
  SensoryQuestionnaireData? data;
  SensoryQuestionFlow? flow;
  Future<SensoryQuestionnaireData>? load;

  /// Last submitted-answer fingerprint, used to detect changed input.
  String? fingerprint;

  bool get isComplete => flow?.current.page == SensoryPage.complete;

  void clear() {
    data = null;
    flow = null;
    load = null;
    fingerprint = null;
  }

  /// Serializes the current answers for change detection.
  String currentFingerprint() {
    return jsonEncode({
      'answers': data!.registry
          .readAnswers(flow!)
          .map((meaning) => meaning.id)
          .toList(),
    });
  }
}
