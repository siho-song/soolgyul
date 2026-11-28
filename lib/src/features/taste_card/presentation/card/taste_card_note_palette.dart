part of '../taste_card_screen.dart';

// A choice shown in pictures, as on a paint chart: the colour of the drink
// as a strip of watercolour dabs, its texture as small drawn glasses, each
// with its name under it and a small arrow over the one picked.

/// How a choice's options are drawn as pictures: one painter an option,
/// how many stand on a line, and how large each is drawn.
class _NotePictures {
  const _NotePictures({
    required this.painters,
    required this.columns,
    required this.size,
  });

  final List<CustomPainter> painters;
  final int columns;
  final double size;

  static const _dabSize = 42.0;
  static const _glassSize = 44.0;

  /// The pictures of [choice]: dabs when its options carry colours, glasses
  /// when every one names a drawing this app has. Null for any other
  /// choice, which stays chips.
  static _NotePictures? of(TasteCardNoteChoiceViewData choice) {
    final options = choice.options;
    if (options.any((option) => option.swatch != null)) {
      return _NotePictures(
        painters: <CustomPainter>[
          for (final option in options)
            _DabPainter(
              color: switch (option.swatch) {
                final swatch? => Color(swatch),
                null => PaperInk.line,
              },
              seed: _paintSeed(option.key),
            ),
        ],
        // Eight colours stand four to a line, ten five to a line.
        columns: options.length <= 8 ? 4 : 5,
        size: _dabSize,
      );
    }
    if (options.every((option) => _GlassPainter.draws(option.icon))) {
      return _NotePictures(
        painters: <CustomPainter>[
          for (final option in options) _GlassPainter(option.icon!),
        ],
        columns: 3,
        size: _glassSize,
      );
    }
    return null;
  }
}

/// The pictures in columns as wide as each other, in the server's order
/// line after line.
class _NotePalette extends StatelessWidget {
  const _NotePalette({
    required this.choice,
    required this.pictures,
    required this.chosen,
    required this.onChoose,
  });

  final TasteCardNoteChoiceViewData choice;
  final _NotePictures pictures;
  final String? chosen;
  final ValueChanged<TasteCardNoteOptionViewData> onChoose;

  /// On a wide page the columns stop growing and stand at the left.
  static const _widestColumn = 96.0;

  /// The room a picture leaves in its column, so neighbours do not touch.
  static const _between = 8.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final column = (constraints.maxWidth / pictures.columns)
          .clamp(0.0, _widestColumn)
          .floorToDouble();
      // Five to a line on a narrow phone, a picture gives a little.
      final size = (column - _between).clamp(0.0, pictures.size);
      return Wrap(
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final (index, option) in choice.options.indexed)
            SizedBox(
              width: column,
              child: _NotePick(
                key: _noteOptionKey(choice, option),
                option: option,
                painter: pictures.painters[index],
                size: size,
                chosen: option.key == chosen,
                onTap: () => onChoose(option),
              ),
            ),
        ],
      );
    },
  );
}

/// The one picked, when the others are put away: its picture, and its name
/// beside it in bold ink.
class _NoteChosenPick extends StatelessWidget {
  const _NoteChosenPick({
    required this.option,
    required this.painter,
    required this.size,
  });

  final TasteCardNoteOptionViewData option;
  final CustomPainter painter;
  final double size;

  static final _name = _DrinkHeaderText.category.copyWith(
    fontWeight: FontWeight.w700,
    color: _TasteCardColors.ink,
  );

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      CustomPaint(size: Size.square(size), painter: painter),
      const SizedBox(width: AppSpacing.s10),
      Expanded(child: Text(option.label, style: _name)),
    ],
  );
}

/// One option to touch: the arrow's place, its picture, then its name in
/// small letters, which may take two lines. Every name is in the text's own
/// dark; the picked one has the arrow and its name in bold.
class _NotePick extends StatelessWidget {
  const _NotePick({
    required this.option,
    required this.painter,
    required this.size,
    required this.chosen,
    required this.onTap,
    super.key,
  });

  final TasteCardNoteOptionViewData option;
  final CustomPainter painter;
  final double size;
  final bool chosen;
  final VoidCallback onTap;

  static const _arrowHeight = 14.0;

  /// A name grows with the reader's text only this far: five stand on a
  /// line of a narrow phone.
  static const _largestNameScale = 1.2;

  static final _name = AppTextStyles.shareLabel.copyWith(
    color: AppColors.textPrimary,
  );
  static final _picked = _name.copyWith(fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chosen,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minimumTapTarget),
        child: Column(
          children: <Widget>[
            // Kept over every picture, so picking one moves nothing.
            CustomPaint(
              size: Size(size, _arrowHeight),
              painter: chosen
                  ? _PickArrowPainter(_paintSeed(option.key))
                  : null,
            ),
            CustomPaint(size: Size.square(size), painter: painter),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Text(
                option.label,
                textAlign: TextAlign.center,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: _largestNameScale),
                style: chosen ? _picked : _name,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A choice of 외관 asked outside the 테이스팅 노트, as the record's first
/// question asks it: the same dabs of colour or small glasses, all of them
/// open. Touching one keeps it; touching the kept one clears it.
class TasteCardAppearancePicker extends StatelessWidget {
  const TasteCardAppearancePicker({
    required this.choice,
    required this.chosen,
    required this.onChoose,
    super.key,
  });

  final TasteCardNoteChoiceViewData choice;

  /// The key of the option kept; null with none.
  final String? chosen;

  /// Called with the option's key, or null when the kept one is cleared.
  final ValueChanged<String?> onChoose;

  void _choose(TasteCardNoteOptionViewData option) =>
      onChoose(option.key == chosen ? null : option.key);

  @override
  Widget build(BuildContext context) {
    if (_NotePictures.of(choice) case final pictures?) {
      return _NotePalette(
        choice: choice,
        pictures: pictures,
        chosen: chosen,
        onChoose: _choose,
      );
    }
    return Wrap(
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final option in choice.options)
          _NoteOptionChip(
            key: _noteOptionKey(choice, option),
            option: option,
            chosen: option.key == chosen,
            onTap: () => _choose(option),
            inkLabel: true,
          ),
      ],
    );
  }
}
