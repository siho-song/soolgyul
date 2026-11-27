part of '../taste_card_screen.dart';

// The aromas of 향, 맛과 질감 and 마무리와 여운 on the 테이스팅 노트 (and
// 질감 on an older card): what the reader marked, in the server's groups by
// how each was taken.

/// How wide an aroma's picture is drawn before its name on the note, at the
/// normal text size, and the gap between the two.
const _notePictureSize = 18.0;
const _notePictureGap = 4.0;

/// One thing the reader marked, as a chip that is not touched, edged and
/// written in its group's colour: wine for one liked, grey-brown for one
/// only noticed, grey for one that was too much, too little or out
/// of place. Its group's name says which.
class _NoteMarkChip extends StatelessWidget {
  const _NoteMarkChip({required this.mark, this.picture});

  final TasteCardNoteMarkViewData mark;

  /// The aroma question's picture that goes before the name, if any.
  final Widget? picture;

  static final _text = _DrinkHeaderText.category.copyWith(
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final ink = _NoteText.inkOf(mark.felt);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: PaperInk.chip,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(color: ink, width: 1.2),
      ),
      // A name too long for its line wraps inside the chip.
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            if (picture case final picture?)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: _notePictureGap),
                  child: picture,
                ),
              ),
            TextSpan(text: mark.label),
          ],
        ),
        style: _text.copyWith(color: ink),
      ),
    );
  }
}

/// The marks of a part in one compact run of chips, in the server's group
/// order, each with the aroma question's picture where it has one. How the
/// reader took each is in its colour: wine for one liked,
/// grey-brown for one only noticed, grey for one that was a burden.
class _NoteAromaChips extends StatelessWidget {
  const _NoteAromaChips({required this.groups});

  final List<TasteCardNoteGroupViewData> groups;

  @override
  Widget build(BuildContext context) {
    final marks = <TasteCardNoteMarkViewData>[
      for (final group in groups) ...group.marks,
    ];
    if (marks.isEmpty) return const _NoteEmpty();
    return ValueListenableBuilder(
      valueListenable: aromaChipByName,
      builder: (context, chips, _) => Wrap(
        spacing: AppSpacing.s6,
        runSpacing: AppSpacing.s6,
        children: <Widget>[
          for (final mark in marks)
            _NoteMarkChip(
              mark: mark,
              picture: AromaPicture.of(
                chips[mark.label],
                size: _notePictureSize,
              ),
            ),
        ],
      ),
    );
  }
}

/// The aromas of a note only read, left to right at their own widths: each
/// its picture and its name on one line, never broken. A line takes the next
/// one while it fits, and at most four; a name wider than the whole line
/// stands alone and is cut short. One liked is in ink, one that was a
/// burden in grey.
class _NoteAromaGrid extends StatelessWidget {
  const _NoteAromaGrid({required this.groups});

  final List<TasteCardNoteGroupViewData> groups;

  static const _perLine = 4;
  static const _gap = 14.0;

  @override
  Widget build(BuildContext context) {
    final marks = <TasteCardNoteMarkViewData>[
      for (final group in groups) ...group.marks,
    ];
    if (marks.isEmpty) return const _NoteEmpty();
    return ValueListenableBuilder(
      valueListenable: aromaChipByName,
      builder: (context, chips, _) => LayoutBuilder(
        builder: (context, constraints) {
          final whole = constraints.maxWidth;
          final scaler = MediaQuery.textScalerOf(context);
          final direction = Directionality.of(context);
          final items = <(Widget, double)>[
            for (final mark in marks)
              _measured(
                context,
                mark,
                AromaPicture.of(chips[mark.label], size: _notePictureSize),
                scaler,
                direction,
              ),
          ];
          // Lines filled greedily by measured width, four at most.
          final lines = <List<(Widget, double)>>[];
          var used = 0.0;
          for (final item in items) {
            final line = lines.isEmpty ? null : lines.last;
            final needed = (line == null || line.isEmpty ? 0 : _gap) + item.$2;
            if (line != null &&
                line.length < _perLine &&
                used + needed <= whole) {
              line.add(item);
              used += needed;
            } else {
              lines.add(<(Widget, double)>[item]);
              used = item.$2;
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final (index, line) in lines.indexed)
                Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      for (final (place, (item, width)) in line.indexed) ...[
                        if (place > 0) const SizedBox(width: _gap),
                        SizedBox(width: width.clamp(0, whole), child: item),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// [mark] as drawn after its [picture], if it has one, and how wide it is
  /// on one line.
  static (Widget, double) _measured(
    BuildContext context,
    TasteCardNoteMarkViewData mark,
    Widget? picture,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final style = DefaultTextStyle.of(context).style.merge(
      _DrinkHeaderText.category.copyWith(
        color:
            mark.felt == TasteCardNoteFelt.liked ||
                mark.felt == TasteCardNoteFelt.noticed
            ? _TasteCardColors.ink
            : PaperInk.grey,
      ),
    );
    final painter = TextPainter(
      text: TextSpan(text: mark.label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    // A hair over, so the drawn line never rounds to a cut.
    final width =
        painter.width.ceilToDouble() +
        1 +
        (picture == null
            ? 0
            : scaler.scale(_notePictureSize) + _notePictureGap);
    painter.dispose();
    final name = Text(
      mark.label,
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    return (
      picture == null
          ? name
          : Row(
              children: <Widget>[
                picture,
                const SizedBox(width: _notePictureGap),
                Expanded(child: name),
              ],
            ),
      width,
    );
  }
}
