import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_chip.dart';
import '../../../../widgets/app_icon.dart';
import '../widgets/onboarding_choice_controls.dart';
import '../../adaptive/direct_aroma_choices.dart';
import '../../adaptive/onboarding_aroma_menu.dart';
import 'aroma_search_sheet.dart';
import 'sensory_question_copy.dart';

const _groupTitleStyle = TextStyle(
  fontSize: 13,
  height: 1.35,
  fontWeight: FontWeight.w700,
  color: AppColors.textPrimary,
);

/// The count of a closed section's hidden chips, at the end of its heading.
final _hiddenCountStyle = AppTextStyles.labelSmall.copyWith(
  fontWeight: FontWeight.w500,
  color: AppColors.textTertiary,
);

/// An aroma question: a search box, a bar of the aromas picked, then the
/// menu of the drink's kind under its headings. A tap on a chip picks its
/// aroma and a second tap unpicks it; as many as were noticed. A heading
/// shows its first six chips; one with more says how many it hides and opens
/// to show them all when tapped. The search box opens the whole dictionary,
/// whose results are picked the same way. The bar holds every aroma picked,
/// wherever it was picked, each with a × that unpicks it.
///
/// Under a page's gauges the question is lighter ([shortList]): in the
/// menu's place stands one list, the aromas picked at the questions before
/// it and then the short list of the drink's kind, six shown and the rest
/// behind its heading. An earlier pick is offered, not answered: it is
/// picked here only once tapped.
///
/// The nose, the palate and the finish each ask with a picker of their own,
/// which holds nothing itself: [selected] is the owner's selection and
/// [onToggle] changes it. Whether an aroma was a burden is said later, on
/// the review page; here one picked is drawn the same either way.
///
/// The search sheet draws the same bar and chips over its results, so what
/// is chosen there is what the question holds.
class AromaPicker extends StatefulWidget {
  const AromaPicker({
    required this.selected,
    required this.onToggle,
    required this.keyPrefix,
    required this.menu,
    required this.label,
    this.shortList,
    this.earlier = const [],
    this.aromaEngine,
    super.key,
  });

  /// The aromas picked, in the order they were picked. Read each time the
  /// picker or its search sheet is drawn, so the owner hands in a live view.
  final Set<String> selected;

  /// A tap on an aroma's chip, here or in the search sheet: the owner picks
  /// it, or unpicks one already picked, and redraws the question.
  final void Function(String key) onToggle;

  /// What a chip is named by before its aroma's key (`aroma:nose:`), which
  /// tells one question's chips from another's.
  final String keyPrefix;
  final OnboardingAromaMenu menu;

  /// The one list shown in the place of the menu's headings; null shows the
  /// menu. The search sheet offers the menu's aromas either way.
  final List<OnboardingAromaChip>? shortList;

  /// The aromas picked at the questions before this one, in the order they
  /// were picked, each once. They lead a [shortList], which then leaves them
  /// out; without one they are not shown.
  final List<String> earlier;

  /// Searches the whole public aroma dictionary; `null` shows no search.
  final DirectAromaChoiceEngine? aromaEngine;

  /// The dictionary word for an aroma.
  final String Function(String key) label;

  @override
  State<AromaPicker> createState() => _AromaPickerState();
}

class _AromaPickerState extends State<AromaPicker> {
  Set<String> get _selected => widget.selected;

  /// The headings opened to show every chip, by their place in the menu;
  /// a short list's heading is kept under the first place.
  final _open = <int>{};

  /// How many chips a closed heading shows.
  static const _closedCount = 6;

  /// The least height of a heading row, which is the tap target of one
  /// that opens.
  static const _headingHeight = 48.0;

  /// The room between a section's last chips and the next heading, wide
  /// enough that a heading reads as the start of its own chips.
  static const _sectionGap = AppSpacing.xxl;

  /// Rings when a pick changes. The open search sheet is not redrawn with
  /// the question, so it listens here.
  final _changes = _AromaChanges();

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }

  /// A tap on a chip, here or in the search sheet: picked, or unpicked if
  /// it already is picked.
  void _toggle(String key) {
    widget.onToggle(key);
    _changes.ring();
  }

  /// What the search sheet names its copies of the bar and the chips by, so
  /// each is found apart from the question's own.
  static const _inSheet = 'search:';

  void _openAromaSearch(DirectAromaChoiceEngine engine) {
    FocusManager.instance.primaryFocus?.unfocus();
    showAromaSearchSheet(
      context,
      engine: engine,
      menu: widget.menu,
      frequent: widget.menu.chipsBeyond(_closedCount, limit: 10),
      changes: _changes,
      pickedBar: () => _selected.isEmpty ? null : _pickedBar(within: _inSheet),
      chip: (key, label) =>
          _chip(key, label, named: '$_inSheet${widget.keyPrefix}$key'),
    );
  }

  /// The chip of an aroma: plain, light green once picked. The search
  /// sheet draws it under its own key ([named]).
  Widget _chip(
    String key,
    String label, {
    bool expand = false,
    String? named,
  }) => AppChip(
    key: ValueKey(named ?? '${widget.keyPrefix}$key'),
    label: label,
    size: onboardingChoiceChipSize,
    variant: AppChipVariant.outline,
    tone: AppChipTone.positive,
    selected: _selected.contains(key),
    expand: expand,
    onPressed: () => _toggle(key),
  );

  /// Two chips per row, each half the width, so the columns line up.
  List<Widget> _rows(List<OnboardingAromaChip> chips) {
    Widget chip(OnboardingAromaChip chip) => _chip(
      chip.key,
      chip.emoji.isEmpty ? chip.label : '${chip.emoji} ${chip.label}',
      expand: true,
    );
    return [
      for (var i = 0; i < chips.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.sm),
          child: Row(
            children: [
              Expanded(child: chip(chips[i])),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: i + 1 < chips.length
                    ? chip(chips[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
    ];
  }

  /// A heading over its chips. One with more than six chips opens and
  /// closes them: the count of what is hidden and a chevron sit at its right
  /// end, and the whole row takes the tap.
  Widget _heading(int index, OnboardingAromaGroup group) {
    final opens = group.chips.length > _closedCount;
    final open = _open.contains(index);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _headingHeight),
      child: Row(
        children: [
          Expanded(child: Text(group.title, style: _groupTitleStyle)),
          if (opens) ...[
            if (!open)
              Text(
                '+${group.chips.length - _closedCount}',
                style: _hiddenCountStyle,
              ),
            const SizedBox(width: AppSpacing.xs),
            AnimatedRotation(
              turns: open ? .5 : 0,
              duration: AppDurations.standard,
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: AppSizes.iconMd,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
    if (!opens) return row;
    void toggle() =>
        setState(() => open ? _open.remove(index) : _open.add(index));
    // A short list's heading already ends in 향.
    final named = group.title.endsWith('향') ? group.title : '${group.title} 향';
    return Semantics(
      button: true,
      expanded: open,
      label: '$named ${open ? '접기' : '모두 보기'}',
      onTap: toggle,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('aroma-section:$index'),
        onTap: toggle,
        child: row,
      ),
    );
  }

  /// A heading and its chips: the first six, or all of them once opened.
  List<Widget> _section(int index, OnboardingAromaGroup group) => [
    _heading(index, group),
    ..._rows(
      _open.contains(index)
          ? group.chips
          : group.chips.take(_closedCount).toList(),
    ),
  ];

  /// The menu, heading by heading.
  List<Widget> _menuSections() => [
    for (final (index, group) in widget.menu.groups.indexed) ...[
      if (index > 0) const SizedBox(height: _sectionGap),
      ..._section(index, group),
    ],
  ];

  /// In the menu's place: one list, led by the aromas picked at the
  /// questions before, then what [shortList] holds besides, so an aroma is
  /// offered once. An earlier pick no menu has a chip for was found by
  /// search and is named by the dictionary's word alone.
  List<Widget> _shortSections(List<OnboardingAromaChip> shortList) {
    final chips = [
      for (final key in widget.earlier)
        OnboardingAromaMenu.chipOf(key) ??
            OnboardingAromaChip(key, '', widget.label(key)),
      for (final chip in shortList)
        if (!widget.earlier.contains(chip.key)) chip,
    ];
    return [
      if (chips.isNotEmpty)
        ..._section(
          0,
          OnboardingAromaGroup(
            title: SensoryQuestionCopy.frequentAromasTitle,
            chips: chips,
          ),
        ),
    ];
  }

  /// The bar of the aromas picked, here or in the search sheet ([within]).
  Widget _pickedBar({String within = ''}) => _PickedAromaBar(
    key: ValueKey('${within}aroma-picked'),
    children: [
      for (final key in _selected)
        _PickedAromaChip(
          key: ValueKey('${within}picked:${widget.keyPrefix}$key'),
          name: widget.label(key),
          onRemove: () => _toggle(key),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final engine = widget.aromaEngine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (engine != null)
          AromaSearchEntry(
            key: const ValueKey('aroma-search:open'),
            onPressed: () => _openAromaSearch(engine),
          ),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _pickedBar(),
        ],
        const SizedBox(height: AppSpacing.sm),
        ...switch (widget.shortList) {
          final shortList? => _shortSections(shortList),
          null => _menuSections(),
        },
      ],
    );
  }
}

class _AromaChanges extends ChangeNotifier {
  void ring() => notifyListeners();
}

/// The bar of the aromas picked: one line that scrolls sideways, and to its
/// end when an aroma joins it, so the newest chip is in sight.
class _PickedAromaBar extends StatefulWidget {
  const _PickedAromaBar({required this.children, super.key});

  /// The chips of the aromas picked, in the order they were picked.
  final List<Widget> children;

  @override
  State<_PickedAromaBar> createState() => _PickedAromaBarState();
}

class _PickedAromaBarState extends State<_PickedAromaBar> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_PickedAromaBar old) {
    super.didUpdateWidget(old);
    if (widget.children.length <= old.children.length) return;
    // The end is known only once the new chip has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppDurations.standard,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _scroll,
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (index, chip) in widget.children.indexed) ...[
          if (index > 0) const SizedBox(width: AppSpacing.sm),
          chip,
        ],
      ],
    ),
  );
}

/// A picked aroma in the bar: its name and a × that unpicks it. The ×
/// alone takes taps.
class _PickedAromaChip extends StatelessWidget {
  const _PickedAromaChip({
    required this.name,
    required this.onRemove,
    super.key,
  });

  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minimumTapTarget),
        child: Center(
          widthFactor: 1,
          child: AppChip(
            label: name,
            size: onboardingChoiceChipSize,
            variant: AppChipVariant.outline,
            tone: AppChipTone.positive,
            selected: true,
            trailingIcon: AppIconAsset.close,
          ),
        ),
      ),
      // The × drawn at the chip's end takes the taps.
      Positioned(
        top: 0,
        right: 0,
        bottom: 0,
        width: AppSizes.minimumTapTarget,
        child: Semantics(
          button: true,
          label: '$name 빼기',
          onTap: onRemove,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: onRemove,
          ),
        ),
      ),
    ],
  );
}
