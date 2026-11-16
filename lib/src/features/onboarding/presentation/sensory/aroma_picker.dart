import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_chip.dart';
import '../widgets/onboarding_choice_controls.dart';
import '../../adaptive/direct_aroma_choices.dart';
import '../../adaptive/onboarding_aroma_menu.dart';
import '../../../../core/sensory/sensory_question_flow.dart';
import '../../../../core/sensory/taste_reactions.dart';
import 'aroma_search_sheet.dart';

const _groupTitleStyle = TextStyle(
  fontSize: 13,
  height: 1.35,
  fontWeight: FontWeight.w700,
  color: AppColors.textPrimary,
);

/// What the first record asks under its menu, over the search box.
const aromaSearchInvitation = '더 세부적인 향을 찾고 싶으신가요?';

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

  static const text = '한 번 터치 👍 좋아요 · 두 번 터치 👎 아쉬워요';

  @override
  Widget build(BuildContext context) =>
      const Text(text, style: AppTextStyles.bodyMuted);
}

/// The aroma question: the drink category's fixed menu under four headings.
/// One tap marks an aroma liked, a second a burden; as many as were noticed.
/// A search box opens the whole dictionary, whose results are these same
/// chips, touched the same way; an aroma found there that the menu lacks
/// joins the chips under the box. A record after the first has the box right
/// under the question; the first record offers it under the menu, to those
/// who look for more than the menu names.
class AromaPicker extends StatefulWidget {
  const AromaPicker({
    required this.flow,
    required this.menu,
    required this.label,
    required this.onChanged,
    this.aromaEngine,
    this.searchFirst = true,
    super.key,
  });

  final SensoryQuestionFlow flow;
  final OnboardingAromaMenu menu;

  /// Searches the whole public aroma dictionary; `null` shows no search.
  final DirectAromaChoiceEngine? aromaEngine;

  /// Whether the search leads the menu; otherwise it closes it, under a
  /// line that asks whether a finer aroma is wanted.
  final bool searchFirst;

  /// The dictionary word for an aroma the menu has no chip for.
  final String Function(String key) label;

  /// Runs the flow change and redraws the question around it.
  final void Function(VoidCallback update) onChanged;

  @override
  State<AromaPicker> createState() => _AromaPickerState();
}

class _AromaPickerState extends State<AromaPicker> {
  Set<String> get _selected => widget.flow.selected(SensorySection.aroma);

  /// The balloon over the chip just liked, saying what a second tap does.
  /// It is shown once, the first time an aroma is picked on this question,
  /// and goes with the next tap, after a moment, or when the page scrolls.
  OverlayEntry? _hint;
  Timer? _hintTimer;
  ScrollPosition? _hintScroll;
  bool _hinted = false;

  static const _hintLife = Duration(seconds: 4);

  void _showHint(BuildContext chip) {
    final box = chip.findRenderObject();
    final overlay = Overlay.maybeOf(chip);
    final overlayBox = overlay?.context.findRenderObject();
    if (box is! RenderBox || overlay == null || overlayBox is! RenderBox) {
      return;
    }
    _hinted = true;
    final anchor = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlayBox),
      box.localToGlobal(
        box.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );
    final entry = OverlayEntry(builder: (_) => _SecondTapHint(anchor: anchor));
    overlay.insert(entry);
    _hint = entry;
    _hintTimer = Timer(_hintLife, _hideHint);
    _hintScroll = Scrollable.maybeOf(chip)?.position?..addListener(_hideHint);
  }

  void _hideHint() {
    _hintTimer?.cancel();
    _hintTimer = null;
    _hintScroll?.removeListener(_hideHint);
    _hintScroll = null;
    _hint?.remove();
    _hint = null;
  }

  @override
  void dispose() {
    _hideHint();
    super.dispose();
  }

  /// A tap on a chip, here or in the search sheet: liked, then a burden,
  /// then off.
  void _toggle(String key) =>
      widget.onChanged(() => widget.flow.cycleAroma(key));

  void _openAromaSearch(DirectAromaChoiceEngine engine) {
    FocusManager.instance.primaryFocus?.unfocus();
    showAromaSearchSheet(
      context,
      search: (query) =>
          engine.search(query).map((option) => option.key).toList(),
      guide: const AromaTapGuide(),
      chip: (key, onPressed) => _chip(
        key,
        widget.label(key),
        named: 'search:aroma:$key',
        onPressed: onPressed,
      ),
      cycle: _toggle,
    );
  }

  /// The chip of an aroma: plain, light green while liked, grey once a
  /// burden. The search sheet draws it under its own key ([named]) and
  /// takes its taps ([onPressed]). The first aroma picked gets the balloon
  /// that says what a second tap does.
  Widget _chip(
    String key,
    String label, {
    bool expand = false,
    String? named,
    VoidCallback? onPressed,
  }) => Builder(
    builder: (chip) => AppChip(
      key: ValueKey(named ?? 'notice:aroma:$key'),
      label: label,
      size: onboardingChoiceChipSize,
      variant: AppChipVariant.outline,
      tone: aromaReactionTone(widget.flow.reactions(SensorySection.aroma)[key]),
      selected: _selected.contains(key),
      expand: expand,
      onPressed: () {
        final picked = _selected.contains(key);
        _hideHint();
        (onPressed ?? () => _toggle(key))();
        if (!_hinted && !picked && _selected.contains(key) && chip.mounted) {
          _showHint(chip);
        }
      },
    ),
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

  /// The search box, and under it the aromas found there that the menu
  /// has no chip for.
  List<Widget> _search(DirectAromaChoiceEngine engine) {
    final menuKeys = widget.menu.keys.toSet();
    final searched = _selected.where((key) => !menuKeys.contains(key));
    return [
      AromaSearchEntry(
        key: const ValueKey('aroma-search:open'),
        onPressed: () => _openAromaSearch(engine),
      ),
      if (searched.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (final key in searched) _chip(key, widget.label(key))],
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.aromaEngine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (engine != null && widget.searchFirst) ...[
          ..._search(engine),
          const SizedBox(height: AppSpacing.lg),
        ],
        for (final (index, group) in widget.menu.groups.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.lg),
          Text(group.title, style: _groupTitleStyle),
          const SizedBox(height: AppSpacing.sm),
          ..._rows(group.chips),
        ],
        if (engine != null && !widget.searchFirst) ...[
          const SizedBox(height: AppSpacing.lg),
          const Text(aromaSearchInvitation, style: _groupTitleStyle),
          const SizedBox(height: AppSpacing.sm),
          ..._search(engine),
        ],
      ],
    );
  }
}

/// The balloon over a chip just liked: a second tap makes it a burden. It
/// takes no taps, so the chip under it is touched through it.
class _SecondTapHint extends StatelessWidget {
  const _SecondTapHint({required this.anchor});

  /// The chip, in the overlay's coordinates.
  final Rect anchor;

  static const text = '한 번 더 누르면\n👎 아쉬워요로 바뀌어요';
  static const _gap = 4.0;
  static const _tail = Size(14, 7);
  static const _margin = AppSpacing.lg;

  @override
  Widget build(BuildContext context) => IgnorePointer(child: _shown());

  Widget _shown() => Material(
    type: MaterialType.transparency,
    child: TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDurations.standard,
      builder: (context, shown, child) => Opacity(opacity: shown, child: child),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: anchor.center.dx - _tail.width / 2,
            top: anchor.top - _gap - _tail.height,
            child: CustomPaint(size: _tail, painter: const _HintTailPainter()),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _HintLayout(
                anchor: anchor,
                bottom: anchor.top - _gap - _tail.height,
                margin: _margin,
              ),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.actionPrimaryStrong,
                  borderRadius: BorderRadius.all(Radius.circular(AppRadii.md)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    text,
                    key: const ValueKey('aroma-second-tap-hint'),
                    textAlign: TextAlign.center,
                    style: _groupTitleStyle.copyWith(
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Sets the balloon over the chip's middle, its foot at [bottom], kept
/// inside the screen's side margins.
class _HintLayout extends SingleChildLayoutDelegate {
  const _HintLayout({
    required this.anchor,
    required this.bottom,
    required this.margin,
  });

  final Rect anchor;
  final double bottom;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(constraints.maxWidth - margin * 2, constraints.maxHeight),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final widest = size.width - margin - childSize.width;
    final left = (anchor.center.dx - childSize.width / 2).clamp(
      margin,
      widest < margin ? margin : widest,
    );
    return Offset(left, bottom - childSize.height);
  }

  @override
  bool shouldRelayout(_HintLayout old) =>
      old.anchor != anchor || old.bottom != bottom || old.margin != margin;
}

/// The balloon's foot: a small triangle pointing down at the chip.
class _HintTailPainter extends CustomPainter {
  const _HintTailPainter();

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close(),
    Paint()..color = AppColors.actionPrimaryStrong,
  );

  @override
  bool shouldRepaint(_HintTailPainter old) => false;
}
