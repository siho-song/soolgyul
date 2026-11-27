import 'package:flutter/material.dart';

import '../../../../core/sensory/sensory_question_flow.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_chip.dart';
import '../../adaptive/onboarding_aroma_menu.dart';
import '../widgets/aroma_picture.dart';
import '../widgets/onboarding_choice_controls.dart';

/// The review page: every answer of the pages before it as a chip, under the
/// heading of where it was answered. A gauge's chip stands under the gauge's
/// own name (단맛, then 미디엄 스위트); the aromas stand together. A heading
/// with nothing answered is left out. Each chip starts plain; a tap marks it as a burden, in the warning
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

  /// The room between one heading's answers and the next heading.
  static const _sectionGap = AppSpacing.xxxl + AppSpacing.lg;

  static const _titles = {
    SensoryReviewSection.nose: '향',
    SensoryReviewSection.palate: '맛 · 질감',
    SensoryReviewSection.flavor: '입안에서 퍼진 풍미',
    SensoryReviewSection.finish: '여운',
  };

  /// An aroma by its name; a gauge by the chosen step's term (드라이), its
  /// axis standing over it.
  String _label(SensoryAnswerItem item) => item.stage != null
      ? aromaLabel(item.key)
      : flow.gauges.of(item.key)!.levelAt(flow.level(item.key)!).term;

  /// What is read out for the chip: a gauge's step with its axis.
  String _spoken(SensoryAnswerItem item) => item.stage != null
      ? _label(item)
      : flow.gauges.of(item.key)!.chipLabel(flow.level(item.key)!);

  /// The section's answers: the gauges two to a line, each chip under the
  /// gauge's name, then the aromas together.
  List<Widget> _answers(List<SensoryAnswerItem> items) {
    final gauges = [
      for (final item in items)
        if (item.stage == null) item,
    ];
    final aromas = [
      for (final item in items)
        if (item.stage != null) item,
    ];
    Widget gauge(SensoryAnswerItem item) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(
            flow.gauges.of(item.key)!.label,
            style: AppTextStyles.bodyMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _chip(item),
      ],
    );
    return [
      for (var i = 0; i < gauges.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: gauge(gauges[i])),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: i + 1 < gauges.length
                    ? gauge(gauges[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      if (aromas.isNotEmpty)
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: aromas.map(_chip).toList(),
        ),
    ];
  }

  /// What goes before the chip's name: an aroma's picture, as it was shown
  /// where it was picked.
  Widget? _picture(SensoryAnswerItem item) => item.stage == null
      ? null
      : AromaPicture.of(
          OnboardingAromaMenu.chipOf(item.key),
          size: aromaChipPictureSize,
        );

  Widget _chip(SensoryAnswerItem item) {
    final label = _label(item);
    final spoken = _spoken(item);
    final burden = flow.isBurden(item);
    void toggle() => onChanged(() => flow.toggleBurden(item));
    return Semantics(
      button: true,
      label: burden ? '$spoken, 아쉬웠던 부분으로 표시됨' : spoken,
      onTap: toggle,
      excludeSemantics: true,
      // Plain, in the text's own dark, until it is marked.
      child: AppChip(
        key: ValueKey('review:${item.id}'),
        label: label,
        leading: _picture(item),
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
            padding: EdgeInsets.only(top: index == 0 ? 0 : _sectionGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    _titles[section]!,
                    style: AppTextStyles.sectionTitle,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ..._answers(items),
              ],
            ),
          ),
      ],
    );
  }
}
