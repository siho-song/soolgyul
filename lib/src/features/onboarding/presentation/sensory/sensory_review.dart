import 'package:flutter/material.dart';

import '../../../../core/sensory/sensory_question_flow.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_chip.dart';
import '../../adaptive/onboarding_aroma_menu.dart';
import '../widgets/onboarding_choice_controls.dart';

/// The review page: every answer of the pages before it as a chip, under the
/// heading of where it was answered. A heading with nothing answered is left
/// out. Each chip starts plain; a tap marks it as a burden, in the warning
/// colour, and a second tap takes the mark away. Any number may be marked.
class SensoryReview extends StatelessWidget {
  const SensoryReview({
    required this.flow,
    required this.aromaLabel,
    required this.onChanged,
    super.key,
  });

  final SensoryQuestionFlow flow;

  /// The dictionary word for an aroma.
  final String Function(String key) aromaLabel;

  /// Runs the flow change and redraws the question around it.
  final void Function(VoidCallback update) onChanged;

  static const _titles = {
    SensoryReviewSection.nose: '코로 맡은 향',
    SensoryReviewSection.palate: '맛 · 질감',
    SensoryReviewSection.flavor: '입안에서 퍼진 풍미',
    SensoryReviewSection.finish: '여운',
  };

  /// An aroma by its name; a gauge by its axis and the chosen step's term
  /// (당도 · 드라이).
  String _label(SensoryAnswerItem item) => item.stage != null
      ? aromaLabel(item.key)
      : flow.gauges.of(item.key)!.chipLabel(flow.level(item.key)!);

  /// What the chip shows: an aroma with the emoji its menu chip has, as it
  /// was shown where it was picked.
  String _shown(SensoryAnswerItem item, String label) {
    if (item.stage == null) return label;
    final emoji = OnboardingAromaMenu.chipOf(item.key)?.emoji ?? '';
    return emoji.isEmpty ? label : '$emoji $label';
  }

  Widget _chip(SensoryAnswerItem item) {
    final label = _label(item);
    final burden = flow.isBurden(item);
    void toggle() => onChanged(() => flow.toggleBurden(item));
    return Semantics(
      button: true,
      label: burden ? '$label, 아쉬웠던 부분으로 표시됨' : label,
      onTap: toggle,
      excludeSemantics: true,
      // Plain, in the text's own dark, until it is marked.
      child: AppChip(
        key: ValueKey('review:${item.id}'),
        label: _shown(item, label),
        size: onboardingChoiceChipSize,
        variant: AppChipVariant.outline,
        tone: burden ? AppChipTone.negative : AppChipTone.neutral,
        selected: burden,
        onPressed: toggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      for (final section in flow.reviewSections)
        if (flow.reviewItems(section) case final items when items.isNotEmpty)
          (section, items),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, (section, items)) in sections.indexed)
          Padding(
            key: ValueKey('review-section:${section.name}'),
            padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    _titles[section]!,
                    style: AppTextStyles.sectionTitleSm,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: items.map(_chip).toList(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
