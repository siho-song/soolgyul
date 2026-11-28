import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_chip.dart';
import '../../../../widgets/app_icon.dart';
import '../widgets/aroma_picture.dart';
import '../widgets/onboarding_choice_controls.dart';
import '../../adaptive/onboarding_aroma_menu.dart';

/// An aroma question: a bar of the aromas picked, then the menu of the
/// drink's kind, one tab a heading (과일, 꽃·허브 …) showing that heading's
/// first six chips and, when it has more, a 더보기 that shows them all and
/// then turns into 접기. A tap on a chip picks its aroma and a second tap
/// unpicks it; as many as were noticed. A picked chip carries the number of
/// its turn in the picking (1 for the first) on its edge. The bar holds
/// every aroma picked, each with a × that unpicks it.
///
/// The nose, the palate and the finish each ask with a picker of their own,
/// which holds nothing itself: [selected] is the owner's selection and
/// [onToggle] changes it. Whether an aroma was a burden is said later, on
/// the review page; here one picked is drawn the same either way.
class AromaPicker extends StatefulWidget {
  const AromaPicker({
    required this.selected,
    required this.onToggle,
    required this.keyPrefix,
    required this.menu,
    required this.label,
    this.showAll = false,
    super.key,
  });

  /// Every chip of each tab at once, with no 더보기; the questionnaire
  /// shows the first ones and a 더보기.
  final bool showAll;

  /// The aromas picked, in the order they were picked. Read each time the
  /// picker is drawn, so the owner hands in a live view.
  final Set<String> selected;

  /// A tap on an aroma's chip: the owner picks
  /// it, or unpicks one already picked, and redraws the question.
  final void Function(String key) onToggle;

  /// What a chip is named by before its aroma's key (`aroma:nose:`), which
  /// tells one question's chips from another's.
  final String keyPrefix;
  final OnboardingAromaMenu menu;

  /// The dictionary word for an aroma.
  final String Function(String key) label;

  @override
  State<AromaPicker> createState() => _AromaPickerState();
}

class _AromaPickerState extends State<AromaPicker> {
  Set<String> get _selected => widget.selected;

  /// The menu's tabs opened by their 더보기, by their place in the menu.
  final _openTabs = <int>{};

  /// The menu's tab shown, by its place in the menu.
  var _tab = 0;

  /// How many chips a tab shows before its 더보기.
  static const _closedCount = 20;

  /// The chip of an aroma: plain, light green once picked, with the
  /// number of its turn on its top left edge.
  Widget _chip(OnboardingAromaChip aroma) {
    final key = aroma.key;
    final chip = AppChip(
      key: ValueKey('${widget.keyPrefix}$key'),
      label: widget.label(key),
      leading: AromaPicture.of(aroma, size: aromaChipPictureSize),
      size: onboardingChoiceChipSize,
      variant: AppChipVariant.outline,
      tone: AppChipTone.positive,
      inkLabel: true,
      selected: _selected.contains(key),
      onPressed: () => widget.onToggle(key),
    );
    final turn = _selected.toList().indexOf(key);
    if (turn < 0) return chip;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        chip,
        Positioned(
          left: -2,
          top: -6,
          child: _PickTurn(
            key: ValueKey('${widget.keyPrefix}$key:turn'),
            turn: turn + 1,
          ),
        ),
      ],
    );
  }

  /// Three chips per row from the left, each as wide as its name, which is
  /// the dictionary's word for its aroma; a row may end short of the edge. A
  /// row too long for the width is drawn a little smaller, whole: a name is
  /// never cut short.
  List<Widget> _rows(List<OnboardingAromaChip> chips) {
    const perRow = 3;
    return [
      for (var i = 0; i < chips.length; i += perRow)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.sm),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var j = i; j < i + perRow && j < chips.length; j++) ...[
                    if (j > i) const SizedBox(width: AppSpacing.sm),
                    _chip(chips[j]),
                  ],
                ],
              ),
            ),
          ),
        ),
    ];
  }

  /// The menu: its headings as tabs, then the chips of the one shown.
  List<Widget> _menuSections() {
    final groups = widget.menu.groups;
    if (groups.isEmpty) return const [];
    final shown = _tab.clamp(0, groups.length - 1);
    return [
      _AromaTabs(
        titles: [for (final group in groups) group.title],
        shown: shown,
        onShow: (index) => setState(() => _tab = index),
      ),
      const SizedBox(height: AppSpacing.lg),
      ..._tabChips(shown, groups[shown].chips),
    ];
  }

  /// A tab's chips: the first six, or all once its 더보기 was tapped, with
  /// the 더보기 or 접기 under them when the tab has more.
  List<Widget> _tabChips(int tab, List<OnboardingAromaChip> chips) {
    if (widget.showAll || chips.length <= _closedCount) return _rows(chips);
    final open = _openTabs.contains(tab);
    return [
      ..._rows(open ? chips : chips.take(_closedCount).toList()),
      _MoreToggle(
        key: ValueKey('aroma-more:$tab'),
        open: open,
        onTap: () =>
            setState(() => open ? _openTabs.remove(tab) : _openTabs.add(tab)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        ..._menuSections(),
      ],
    );
  }
}

/// The menu's headings as a line of tabs that scrolls sideways; the one
/// shown is in dark ink over a short bar, the others in grey.
class _AromaTabs extends StatelessWidget {
  const _AromaTabs({
    required this.titles,
    required this.shown,
    required this.onShow,
  });

  final List<String> titles;
  final int shown;
  final ValueChanged<int> onShow;

  static const _bar = 2.0;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (index, title) in titles.indexed)
          Semantics(
            button: true,
            selected: index == shown,
            child: InkWell(
              key: ValueKey('aroma-tab:$index'),
              onTap: () => onShow(index),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSizes.minimumTapTarget,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : AppSpacing.md,
                    right: AppSpacing.md,
                  ),
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.body.copyWith(
                            color: index == shown
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                            fontWeight: index == shown
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          height: _bar,
                          color: index == shown
                              ? AppColors.textPrimary
                              : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The number of a picked aroma's turn, in a small dark circle.
class _PickTurn extends StatelessWidget {
  const _PickTurn({required this.turn, super.key});

  final int turn;

  static const _size = 20.0;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Container(
        width: _size,
        height: _size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.textPrimary,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$turn',
          textScaler: TextScaler.noScaling,
          style: AppTextStyles.caption.copyWith(
            height: 1,
            fontWeight: FontWeight.w700,
            color: AppColors.textOnPrimary,
          ),
        ),
      ),
    ),
  );
}

/// The 더보기 under a tab's first chips, or 접기 once the tab shows them
/// all: centred, with a chevron down or up.
class _MoreToggle extends StatelessWidget {
  const _MoreToggle({required this.open, required this.onTap, super.key});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = open ? '접기' : '더보기';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Semantics(
        button: true,
        expanded: open,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minimumTapTarget,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppIcon(
                  open ? AppIconAsset.chevronUp : AppIconAsset.expand,
                  size: AppSizes.iconMd,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
