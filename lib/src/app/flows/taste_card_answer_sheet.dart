import 'package:flutter/material.dart';

import '../../core/sensory/sensory_question_flow.dart';
import '../../features/onboarding/data/sensory_questionnaire_data.dart';
import '../../features/onboarding/presentation/sensory_questionnaire_screen.dart';
import '../../features/taste_card/data/sensory_submission.dart';
import '../../widgets/app_sheet.dart';

/// The questions each part of the questionnaire answers, by their keys.
const _questionKeys = <SensoryPart, List<String>>{
  SensoryPart.revisit: <String>['sensory_revisit'],
  SensoryPart.aroma: <String>['sensory_aroma'],
  SensoryPart.palate: <String>['sensory_taste', 'sensory_mouthfeel'],
  SensoryPart.finish: <String>['sensory_finish'],
};

/// Opens the questions of [part] again in a tall sheet, as the record flow
/// asks them, filled with [answers]: the record's chosen option ids by
/// question key. 완료 on the last question closes the sheet with the part's
/// questions as now answered, by question key; a sheet closed any other way
/// gives null and changes nothing.
Future<Map<String, List<String>>?> showTasteCardAnswerSheet(
  BuildContext context, {
  required SensoryQuestionnaireData questions,
  required SensoryPart part,
  required Map<String, List<String>> answers,
}) => showAppSheet<Map<String, List<String>>>(
  context: context,
  tall: true,
  builder: (_) =>
      _AnswerSheet(questions: questions, part: part, answers: answers),
);

class _AnswerSheet extends StatefulWidget {
  const _AnswerSheet({
    required this.questions,
    required this.part,
    required this.answers,
  });

  final SensoryQuestionnaireData questions;
  final SensoryPart part;
  final Map<String, List<String>> answers;

  @override
  State<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends State<_AnswerSheet> {
  /// Holds every answer of the record, and walks the part's pages alone.
  late final SensoryQuestionFlow _flow = widget.questions.registry.createFlow(
    widget.questions.asked,
    widget.part,
  );

  /// The answers as the sheet opened with them. An answer the questions no
  /// longer offer is not among them.
  late final Map<String, List<String>> _opened;

  @override
  void initState() {
    super.initState();
    widget.questions.registry.restoreAnswers(_flow, <String>[
      for (final chosen in widget.answers.values) ...chosen,
    ]);
    _opened = _answered();
  }

  Map<String, List<String>> _answered() => SensorySubmission.optionKeys(
    flow: _flow,
    registry: widget.questions.registry,
  );

  void _done() {
    final answered = _answered();
    Navigator.of(context).pop(<String, List<String>>{
      for (final key in _questionKeys[widget.part]!)
        // A question left as it opened keeps what the record holds, whole.
        key: _same(answered[key]!, _opened[key]!)
            ? widget.answers[key] ?? const <String>[]
            : answered[key]!,
    });
  }

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  @override
  Widget build(BuildContext context) => SafeArea(
    key: const ValueKey<String>('taste-card-answer-sheet'),
    top: false,
    child: SensoryQuestionnaireScreen(
      flow: _flow,
      registry: widget.questions.registry,
      aromaMenu: widget.questions.aromaMenu,
      aromaEngine: widget.questions.aromaEngine,
      // Nothing is kept until 완료.
      onChanged: () {},
      onComplete: _done,
    ),
  );
}
