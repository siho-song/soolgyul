part of '../taste_card_screen.dart';

// What the 테이스팅 노트 sheet is written with: its text, the rows of 맛
// 밸런스 and 여운 밸런스 (words on a card answered on the gauges, the
// bottle's bars on an older one), a memo line, the small arrow of what is touched to
// change it and the line of a part nobody answered.

abstract final class _NoteText {
  /// 맛 밸런스, 입안에서 느껴진 풍미, 질감.
  static const part = TasteCardGuideText.label;

  /// A fact's name, a group's name, the line of an empty part, the line
  /// that asks for a choice.
  static final muted = _DrinkHeaderText.category.copyWith(color: PaperInk.grey);

  /// The name of a choice (색, 점성), over what asks for it.
  static final choice = _DrinkHeaderText.category.copyWith(
    fontWeight: FontWeight.w600,
    color: PaperInk.grey,
  );

  /// The colour a group's name and its chips are written in, by how the
  /// reader took what is in it.
  static Color inkOf(TasteCardNoteFelt felt) => switch (felt) {
    TasteCardNoteFelt.liked => _TasteCardColors.wine,
    TasteCardNoteFelt.noticed => PaperInk.noticed,
    TasteCardNoteFelt.less ||
    TasteCardNoteFelt.more ||
    TasteCardNoteFelt.burden => PaperInk.grey,
  };

  /// The name of a group: 마음에 들었어요, 느껴졌어요, 부담됐어요.
  static TextStyle group(TasteCardNoteFelt felt) => _DrinkHeaderText.category
      .copyWith(fontWeight: FontWeight.w600, color: inkOf(felt));
  static final value = TasteCardGuideText.caption.copyWith(
    fontWeight: FontWeight.w500,
    color: _TasteCardColors.ink,
  );

  /// The reader's own words about a taste.
  static const said = _DrinkHeaderText.category;

  /// The term of the step the reader chose on a gauge, in the colour of how
  /// it was taken.
  static TextStyle step(TasteCardNoteFelt felt) =>
      said.copyWith(fontWeight: FontWeight.w600, color: inkOf(felt));
}

/// The one line of a part the reader left nothing in, so the sheet keeps
/// its shape. Where the part can be answered, it offers to.
class _NoteEmpty extends StatelessWidget {
  const _NoteEmpty({this.answerable = false});

  final bool answerable;

  @override
  Widget build(BuildContext context) => answerable
      ? Text(_noteAddWording, style: _DrinkHeaderText.addPrice)
      : Text('남긴 기록이 없어요', style: _NoteText.muted);
}

/// The small light arrow at the end of what is touched to enter or change
/// it: a cell of the head, a memo line, a look already chosen.
class _NoteChevron extends StatelessWidget {
  const _NoteChevron();

  static const size = 16.0;

  /// The width the arrow takes of its line, with the gap before it.
  static const room = size + AppSpacing.xxs;

  /// Lighter than the words it follows.
  static final _ink = PaperInk.grey.withValues(alpha: .55);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xxs),
    child: Icon(Icons.chevron_right, size: size, color: _ink),
  );
}

/// 맛 밸런스 or 여운 밸런스: one row per gauge, in the server's order. With
/// none the part says so, and offers to be answered where it can be.
///
/// A card answered on the gauges ([worded]) lists what the reader chose in
/// words alone, and a gauge they left unanswered is not listed, whatever
/// the catalog knows of the bottle. A card answered before them draws the
/// bottle's level on each row.
class _NoteBalanceRows extends StatelessWidget {
  const _NoteBalanceRows({
    required this.rows,
    required this.worded,
    this.answerable = false,
  });

  final List<TasteCardNoteBalanceViewData> rows;
  final bool worded;
  final bool answerable;

  @override
  Widget build(BuildContext context) {
    if (worded) {
      final answered = <TasteCardNoteBalanceViewData>[
        for (final row in rows)
          if (row.level != null && row.said != null) row,
      ];
      return answered.isEmpty
          ? _NoteEmpty(answerable: answerable)
          : _NoteStepRows(rows: answered);
    }
    return rows.isEmpty
        ? _NoteEmpty(answerable: answerable)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final (index, entry) in rows.indexed) ...<Widget>[
                if (index > 0) const SizedBox(height: AppSpacing.md),
                _NoteBalanceRow(entry: entry),
              ],
            ],
          );
  }
}

/// The gauges the reader answered, one line each: the gauge's name, then
/// the term of the step they chose (당도, 드라이), in two columns. A step
/// they liked follows a heart, in the liked colour; one that was a burden
/// is grey with no icon, and starts where the others' terms do.
class _NoteStepRows extends StatelessWidget {
  const _NoteStepRows({required this.rows});

  /// Rows that hold a step and its term.
  final List<TasteCardNoteBalanceViewData> rows;

  static const _heartRoom = AppSizes.iconXs + AppSpacing.xs;

  Widget _term(TasteCardNoteBalanceViewData row, {required bool hearts}) {
    final liked = row.felt == TasteCardNoteFelt.liked;
    return Row(
      children: <Widget>[
        if (liked)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: SvgPicture.asset(
              tasteCardTagIcons[TasteCardTagKind.liked]!,
              width: AppSizes.iconXs,
              height: AppSizes.iconXs,
              colorFilter: ColorFilter.mode(
                _tagIconColor(TasteCardTagKind.liked),
                BlendMode.srcIn,
              ),
            ),
          )
        else if (hearts)
          const SizedBox(width: _heartRoom),
        Expanded(
          child: KeptText(
            row.said!,
            style: _NoteText.step(row.felt ?? TasteCardNoteFelt.noticed),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hearts = rows.any((row) => row.felt == TasteCardNoteFelt.liked);
    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        for (final (index, row) in rows.indexed)
          TableRow(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.only(
                  top: index == 0 ? 0 : AppSpacing.sm,
                  right: AppSpacing.xl,
                ),
                child: Text(row.label, style: LevelGauge.nameStyle),
              ),
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.sm),
                child: _term(row, hearts: hearts),
              ),
            ],
          ),
      ],
    );
  }
}

/// One gauge of 맛 밸런스 or 여운 밸런스: the bottle's own level on the app's
/// gauge with its word, and under it what the reader said of it, or the
/// step they chose for it. A gauge whose level is not known has no bar: its
/// name, then the remark where the other rows' bars start. A gauge that
/// runs between two characters names them under the remark.
class _NoteBalanceRow extends StatelessWidget {
  const _NoteBalanceRow({required this.entry});

  final TasteCardNoteBalanceViewData entry;

  @override
  Widget build(BuildContext context) {
    final mark = entry.mark;
    final labelWidth = LevelGauge.labelWidthOf(entry.label);
    final remark = _NoteRemark.of(entry);
    final said = switch (entry.ends) {
      null => remark,
      (final low, final high) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ?remark,
          Text('$low ↔ $high', style: _NoteText.muted),
        ],
      ),
    };
    if (mark == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          // A name wider than the gauges' room for one keeps its line and
          // starts its remark a little later.
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: labelWidth),
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Text(entry.label, style: LevelGauge.nameStyle),
            ),
          ),
          if (said != null) Expanded(child: said),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LevelGauge.worded(label: entry.label, mark: mark, word: entry.word),
        if (said != null)
          Padding(
            padding: EdgeInsets.only(left: labelWidth, top: AppSpacing.xxs),
            child: said,
          ),
      ],
    );
  }
}

/// What the reader said of a taste: a heart before one they liked, then
/// their words. A step chosen on a gauge is written in the colour of how
/// it was taken, as a mark's chip is, with the step in grey after it (드라이
/// 2/5); one that was a burden has that colour alone, no icon.
class _NoteRemark extends StatelessWidget {
  const _NoteRemark({
    required this.felt,
    required this.said,
    required this.level,
  });

  final TasteCardNoteFelt? felt;
  final String? said;

  /// The step chosen on the gauge, 1 to 5; null on a row without one.
  final int? level;

  /// Null when the reader said nothing of the taste.
  static _NoteRemark? of(TasteCardNoteBalanceViewData entry) =>
      entry.felt != TasteCardNoteFelt.liked &&
          entry.said == null &&
          entry.level == null
      ? null
      : _NoteRemark(felt: entry.felt, said: entry.said, level: entry.level);

  @override
  Widget build(BuildContext context) => KeptText.rich(
    TextSpan(
      style: _NoteText.said,
      children: <InlineSpan>[
        if (felt == TasteCardNoteFelt.liked)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: SvgPicture.asset(
                tasteCardTagIcons[TasteCardTagKind.liked]!,
                width: AppSizes.iconXs,
                height: AppSizes.iconXs,
                colorFilter: ColorFilter.mode(
                  _tagIconColor(TasteCardTagKind.liked),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        if (said != null)
          TextSpan(
            text: said,
            // The words of a card answered before the gauges stay plain.
            style: switch ((level, felt)) {
              (_?, final felt?) => _NoteText.step(felt),
              _ => null,
            },
          ),
        if (level case final level?)
          TextSpan(
            text: said == null ? '$level/5' : ' $level/5',
            style: _NoteText.muted,
          ),
      ],
    ),
  );
}

/// A memo under a line: its name, then the owner's words and the small
/// arrow (총평 : 첫 싱글 몰트로 좋았다 ›). It is touched to write or change
/// it, and one not written yet offers to (메모 : + 입력 ›).
class _NoteMemoRow extends StatelessWidget {
  const _NoteMemoRow({
    required this.label,
    required this.memo,
    required this.onTap,
    super.key,
  });

  final String label;

  /// Blank without one.
  final String memo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final row = DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _TasteCardColors.ticketLine)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: '$label : ', style: _NoteText.muted),
                    memo.isEmpty
                        ? TextSpan(
                            text: _noteAddWording,
                            style: _DrinkHeaderText.addPrice,
                          )
                        : TextSpan(text: memo),
                  ],
                ),
                style: _NoteText.value,
              ),
            ),
            const _NoteChevron(),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// What the card's header says where something can be added.
const _noteAddWording = '+ 입력';
