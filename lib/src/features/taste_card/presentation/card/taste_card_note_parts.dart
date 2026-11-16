part of '../taste_card_screen.dart';

// What the 테이스팅 노트 sheet is written with: its text, a 맛 밸런스 row, a
// memo line, the small arrow of what is touched to change it and the line
// of a part nobody answered.

abstract final class _NoteText {
  /// 맛 밸런스, 질감.
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

/// One taste of 맛 밸런스: the bottle's own level on the app's gauge with
/// its word, and under it what the reader said of it. A taste whose level
/// is not known has no gauge: its name, then the remark where the other
/// rows' bars start.
class _NoteBalanceRow extends StatelessWidget {
  const _NoteBalanceRow({required this.entry});

  final TasteCardNoteBalanceViewData entry;

  @override
  Widget build(BuildContext context) {
    final mark = entry.mark;
    final labelWidth = LevelGauge.labelWidthOf(entry.label);
    final remark = _NoteRemark.of(entry);
    if (mark == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          SizedBox(
            width: labelWidth,
            child: Text(entry.label, style: LevelGauge.nameStyle),
          ),
          if (remark != null) Expanded(child: remark),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LevelGauge.worded(label: entry.label, mark: mark, word: entry.word),
        if (remark != null)
          Padding(
            padding: EdgeInsets.only(left: labelWidth, top: AppSpacing.xxs),
            child: remark,
          ),
      ],
    );
  }
}

/// What the reader said of a taste: the icon of how they took it, then
/// their words.
class _NoteRemark extends StatelessWidget {
  const _NoteRemark({required this.kind, required this.said});

  final TasteCardTagKind? kind;
  final String? said;

  /// Null when the reader said nothing of the taste.
  static _NoteRemark? of(TasteCardNoteBalanceViewData entry) {
    final kind = entry.felt?.tagKind;
    return kind == null && entry.said == null
        ? null
        : _NoteRemark(kind: kind, said: entry.said);
  }

  @override
  Widget build(BuildContext context) => KeptText.rich(
    TextSpan(
      style: _NoteText.said,
      children: <InlineSpan>[
        if (kind case final kind?)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: SvgPicture.asset(
                tasteCardTagIcons[kind]!,
                width: AppSizes.iconXs,
                height: AppSizes.iconXs,
                colorFilter: ColorFilter.mode(
                  _tagIconColor(kind),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        if (said != null) TextSpan(text: said),
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
