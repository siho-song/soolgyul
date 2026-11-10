import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_chip.dart';
import '../../../../core/sensory/finish_choices.dart';
import '../../../../core/sensory/sensory_question_flow.dart';
import '../widgets/onboarding_choice_controls.dart';

/// 마무리 질문의 선택지: 좋았던·아쉬웠던 마무리 묶음을 두 칸짜리 칩으로 모두
/// 보여 줍니다. 묶음 안의 순서는 길이, 정리, 잔향이에요.
class SensoryFinishChoices extends StatelessWidget {
  const SensoryFinishChoices({
    required this.flow,
    required this.onChanged,
    super.key,
  });

  final SensoryQuestionFlow flow;

  /// Runs the flow change and redraws the question around it.
  final void Function(VoidCallback update) onChanged;

  static const _groups = <bool, String>{true: '좋았던 마무리', false: '아쉬웠던 마무리'};

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final positive in _groups.keys)
        _group(
          positive,
          FinishOption.values.where((o) => o.positive == positive).toList(),
        ),
    ],
  );

  Widget _group(bool positive, List<FinishOption> options) => Column(
    key: ValueKey('finish-group:${positive ? 'liked' : 'disliked'}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.lg,
          bottom: AppSpacing.sm,
        ),
        child: Semantics(
          header: true,
          child: Text(
            _groups[positive]!,
            style: AppTextStyles.onboardingOptionLabel,
          ),
        ),
      ),
      // Two chips per row, each half the width, so the columns line up.
      for (var i = 0; i < options.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.sm),
          child: Row(
            children: [
              Expanded(child: _chip(options[i])),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: i + 1 < options.length
                    ? _chip(options[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _chip(FinishOption option) => AppChip(
    key: ValueKey('finish:${option.name}'),
    label: option.chip,
    size: onboardingChoiceChipSize,
    variant: AppChipVariant.outline,
    selected: flow.finish.selected.contains(option),
    expand: true,
    onPressed: () => onChanged(() => flow.finish.toggle(option)),
  );
}
