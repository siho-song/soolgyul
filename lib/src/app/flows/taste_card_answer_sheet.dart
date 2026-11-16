import 'package:flutter/material.dart';

import '../../core/sensory/sensory_meanings.dart';
import '../../core/sensory/sensory_question_flow.dart';
import '../../features/onboarding/data/sensory_questionnaire_data.dart';
import '../../features/onboarding/presentation/sensory_questionnaire_screen.dart';
import '../../widgets/app_sheet.dart';

/// Opens the page of [part] again in a tall sheet, as the record flow asks
/// it, filled with [answers]: the record's chosen option ids by question
/// key. The review of the part's answers follows the page, and its 저장
/// closes the sheet with the part's questions as now answered, by question
/// key; a part left with nothing to review closes on 완료. A sheet closed
/// any other way gives null and changes nothing.
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
    widget.questions.gauges,
    only: widget.part,
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

  Map<String, List<String>> _answered() =>
      widget.questions.registry.readAnswers(_flow);

  void _done() {
    final answered = _answered();
    Navigator.of(context).pop(<String, List<String>>{
      for (final key in SensoryQuestionKeys.of(widget.part))
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
      // Nothing is kept until the sheet's last button.
      onChanged: () {},
      onComplete: _done,
    ),
  );
}
