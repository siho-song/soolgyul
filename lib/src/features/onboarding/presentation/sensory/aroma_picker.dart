import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_chip.dart';
import '../components/onboarding_choice_controls.dart';
import '../../adaptive/direct_aroma_choices.dart';
import '../../adaptive/onboarding_aroma_menu.dart';
import '../../adaptive/sensory_question_flow.dart';
import '../../adaptive/taste_reactions.dart';
import 'aroma_search_sheet.dart';

const _groupTitleStyle = TextStyle(
  fontSize: 13,
  height: 1.35,
  fontWeight: FontWeight.w700,
  color: AppColors.textPrimary,
);

/// A picked aroma is light green while liked and grey once a burden.
AppChipTone aromaReactionTone(TasteReaction? reaction) => switch (reaction) {
  TasteReaction.liked => AppChipTone.positive,
  TasteReaction.disliked => AppChipTone.negative,
  _ => AppChipTone.brand,
};

/// One quiet grey line under the aroma question that stays while the user
/// picks: one tap is 좋아요, a second 아쉬워요. Plain text, so it reads as a
/// guide and not as more buttons.
class AromaTapGuide extends StatelessWidget {
  const AromaTapGuide({super.key});

  static const text = '1번 탭 👍 좋아요  ·  2번 탭 👎 아쉬워요';

  @override
  Widget build(BuildContext context) =>
      const Text(text, style: AppTextStyles.descriptionTrailing);
}

/// The aroma question: the drink category's fixed menu under four headings.
/// One tap marks an aroma liked, a second a burden; five at most, counted on
/// the question's description line. The app's record flow also has a search
/// box right under the question; an aroma found there that the menu lacks
/// joins the chips above the menu. The first record keeps the menu alone.
class AromaPicker extends StatefulWidget {
  const AromaPicker({
    required this.flow,
    required this.menu,
    required this.label,
    required this.onChanged,
    this.aromaEngine,
    super.key,
  });

  final SensoryQuestionFlow flow;
  final OnboardingAromaMenu menu;

  /// Searches the whole public aroma dictionary; `null` shows no search.
  final DirectAromaChoiceEngine? aromaEngine;

  /// The dictionary word for an aroma the menu has no chip for.
  final String Function(String key) label;

  /// Runs the flow change and redraws the question around it.
  final void Function(VoidCallback update) onChanged;

  @override
  State<AromaPicker> createState() => _AromaPickerState();
}

class _AromaPickerState extends State<AromaPicker> {
  bool _selectionLimitReached = false;

  Set<String> get _selected => widget.flow.selected(SensorySection.aroma);

  bool get _atLimit => _selected.length == maxAromaSelections;

  void _toggle(String key) {
    if (!_selected.contains(key) && _atLimit) {
      setState(() => _selectionLimitReached = true);
      return;
    }
    setState(() => _selectionLimitReached = false);
    widget.onChanged(() => widget.flow.cycleAroma(key));
  }

  /// The search sheet adds an aroma as liked and removes it on a second
  /// tap; liked or burden is set on the chip. The sheet says so itself
  /// when the limit keeps an aroma out.
  bool _toggleFromSearch(String key) {
    if (_selected.contains(key)) {
      widget.onChanged(
        () => widget.flow.toggleNotice(SensorySection.aroma, key),
      );
      return true;
    }
    if (_atLimit) return false;
    setState(() => _selectionLimitReached = false);
    widget.onChanged(() => widget.flow.cycleAroma(key));
    return true;
  }

  void _openAromaSearch(DirectAromaChoiceEngine engine) {
    FocusManager.instance.primaryFocus?.unfocus();
    showAromaSearchSheet(
      context,
      search: (query) =>
          engine.search(query).map((option) => option.key).toList(),
      label: widget.label,
      isSelected: _selected.contains,
      selectedCount: () => _selected.length,
      toggle: _toggleFromSearch,
    );
  }

  AppChip _chip(String key, String label, {bool expand = false}) => AppChip(
    key: ValueKey('notice:aroma:$key'),
    label: label,
    size: onboardingChoiceChipSize,
    variant: AppChipVariant.outline,
    tone: aromaReactionTone(widget.flow.reactions(SensorySection.aroma)[key]),
    selected: _selected.contains(key),
    expand: expand,
    onPressed: () => _toggle(key),
  );

  /// Two chips per row, each half the width, so the columns line up.
  List<Widget> _rows(List<OnboardingAromaChip> chips) => [
    for (var i = 0; i < chips.length; i += 2)
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: _chip(
                chips[i].key,
                '${chips[i].emoji} ${chips[i].label}',
                expand: true,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: i + 1 < chips.length
                  ? _chip(
                      chips[i + 1].key,
                      '${chips[i + 1].emoji} ${chips[i + 1].label}',
                      expand: true,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final menuKeys = widget.menu.keys.toSet();
    final searched = _selected.where((key) => !menuKeys.contains(key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.aromaEngine case final engine?) ...[
          AromaSearchEntry(
            key: const ValueKey('aroma-search:open'),
            onPressed: () => _openAromaSearch(engine),
          ),
          if (searched.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final key in searched) _chip(key, widget.label(key)),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
        for (final (index, group) in widget.menu.groups.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.lg),
          Text(group.title, style: _groupTitleStyle),
          const SizedBox(height: AppSpacing.sm),
          ..._rows(group.chips),
        ],
        if (_selectionLimitReached)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('향은 최대 $maxAromaSelections개까지 고를 수 있어요.'),
          ),
      ],
    );
  }
}
