part of '../taste_card_screen.dart';

// 향, 질감 and 여운 on the 테이스팅 노트: what the reader marked, in the
// server's groups by how each was taken.

/// 향, 질감 or 여운 as the server grouped it by how each thing was taken:
/// the group's name as a small heading, then its marks as chips. The groups
/// are drawn as given, in order; one with nothing in it is left out, and
/// with none left the part says so.
class _NoteMarkGroups extends StatelessWidget {
  const _NoteMarkGroups({required this.groups, this.answerable = false});

  final List<TasteCardNoteGroupViewData> groups;

  /// Whether the part can be answered here, which an empty one offers.
  final bool answerable;

  @override
  Widget build(BuildContext context) {
    final shown = <TasteCardNoteGroupViewData>[
      for (final group in groups)
        if (group.marks.isNotEmpty) group,
    ];
    if (shown.isEmpty) return _NoteEmpty(answerable: answerable);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, group) in shown.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: AppSpacing.s14),
          Text(group.label, style: _NoteText.group(group.marks.first.felt)),
          const SizedBox(height: AppSpacing.s6),
          Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.s6,
            children: <Widget>[
              for (final mark in group.marks) _NoteMarkChip(mark: mark),
            ],
          ),
        ],
      ],
    );
  }
}

/// One thing the reader marked, as a chip that is not touched, edged and
/// written in its group's colour: wine for one liked, grey-brown for one
/// only noticed, grey for one that was too much, too little or out
/// of place, with the arrow of which way.
class _NoteMarkChip extends StatelessWidget {
  const _NoteMarkChip({required this.mark});

  final TasteCardNoteMarkViewData mark;

  static final _text = _DrinkHeaderText.category.copyWith(
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final ink = _NoteText.inkOf(mark.felt);
    // ↓ for too much, ↑ for too little; the group says the rest.
    final icon = switch (mark.felt) {
      TasteCardNoteFelt.less => tasteCardTagIcons[TasteCardTagKind.less],
      TasteCardNoteFelt.more => tasteCardTagIcons[TasteCardTagKind.more],
      _ => null,
    };
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // A name too long for its line wraps inside the chip.
          Flexible(
            child: Text(mark.label, style: _text.copyWith(color: ink)),
          ),
          if (icon != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            SvgPicture.asset(
              icon,
              width: AppSizes.iconXs,
              height: AppSizes.iconXs,
              colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
            ),
          ],
        ],
      ),
    );
  }
}
