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

  bool get isComplete => flow?.current == SensoryPage.complete;

  /// Forgets the answers unless the drink chosen is the one they are
  /// about: going back to the search and choosing [sameDrink] again finds
  /// the questions as they were left. Answers already sent (the flow stands
  /// past its last question) are not kept; the next record starts clean.
  void keepFor({required bool sameDrink}) {
    if (!sameDrink || isComplete) clear();
  }

  void clear() {
    data = null;
    flow = null;
    load = null;
    fingerprint = null;
  }

  /// Serializes the current answers for change detection.
  String currentFingerprint() {
    return jsonEncode({'answers': data!.registry.readAnswers(flow!)});
  }
}
