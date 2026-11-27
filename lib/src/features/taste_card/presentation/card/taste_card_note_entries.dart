part of '../taste_card_screen.dart';

// The choices the owner makes on the 테이스팅 노트 in edit mode: the colour
// and the texture in 상세 기록, and how it was drunk and 재음용 의사 in sheets
// opened from the form. Each goes into the form, kept on 완료.

/// The option of [choice] whose key is [key]; null for none.
TasteCardNoteOptionViewData? _optionOf(
  TasteCardNoteChoiceViewData choice,
  String? key,
) {
  for (final option in choice.options) {
    if (option.key == key) return option;
  }
  return null;
}

/// One choice of 외관 in its row of 상세 기록. Read, it is the one chosen:
/// its picture with its name beside it, or its chip. In edit mode
/// ([onChoose]) every option lies open, as chips or, for a colour or a
/// texture, as pictures, the kept one marked; touching another keeps that
/// instead and touching the kept one clears it.
/// How large a chosen colour or texture is drawn on a note only read.
const _readPictureSize = 26.0;

class _NoteChoice extends StatelessWidget {
  const _NoteChoice({
    required this.choice,
    required this.chosenKey,
    this.onChoose,
  });

  final TasteCardNoteChoiceViewData choice;
  final String? chosenKey;
  final ValueChanged<String?>? onChoose;

  @override
  Widget build(BuildContext context) {
    final chosen = _optionOf(choice, chosenKey);
    // Null draws chips.
    final pictures = _NotePictures.of(choice);
    final onChoose = this.onChoose;
    if (onChoose == null) {
      if (chosen == null) return const SizedBox.shrink();
      return KeyedSubtree(
        key: _noteOptionKey(choice, chosen),
        child: Align(
          alignment: Alignment.centerLeft,
          child: pictures == null
              ? _NoteOptionChip(option: chosen, chosen: true)
              : _NoteChosenPick(
                  option: chosen,
                  painter: pictures.painters[choice.options.indexOf(chosen)],
                  // Small when read, so the row stays compact.
                  size: _readPictureSize,
                ),
        ),
      );
    }
    void choose(TasteCardNoteOptionViewData option) =>
        onChoose(option == chosen ? null : option.key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (choice.prompt case final prompt?) ...<Widget>[
          Text(prompt, style: _NoteText.muted),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (pictures != null)
          _NotePalette(
            choice: choice,
            pictures: pictures,
            chosen: chosen?.key,
            onChoose: choose,
          )
        else
          Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final option in choice.options)
                _NoteOptionChip(
                  key: _noteOptionKey(choice, option),
                  option: option,
                  chosen: option == chosen,
                  onTap: () => choose(option),
                ),
            ],
          ),
      ],
    );
  }
}

/// The key of an option's chip or picture, by which it is found and
/// touched.
Key _noteOptionKey(
  TasteCardNoteChoiceViewData choice,
  TasteCardNoteOptionViewData option,
) => _noteChipKey(choice.field, option.key);

Key _noteChipKey(String field, String option) =>
    ValueKey<String>('taste-card-note-option-$field-$option');

/// An option as a chip: a quiet paper chip, and the chosen one a ticket
/// edged and written in the card's wine. An [outlined] one, in a sheet of
/// choices, is not chosen as an empty chip edged in grey with its words in
/// ink. With [onTap] it is touched to choose it.
class _NoteOptionChip extends StatelessWidget {
  const _NoteOptionChip({
    required this.option,
    required this.chosen,
    this.onTap,
    this.outlined = false,
    super.key,
  });

  final TasteCardNoteOptionViewData option;
  final bool chosen;
  final VoidCallback? onTap;
  final bool outlined;

  static final _outlinedPlain = _DrinkHeaderText.category.copyWith(
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static final _plain = _DrinkHeaderText.category.copyWith(
    fontWeight: FontWeight.w500,
    color: PaperInk.grey,
  );
  static final _chosen = _DrinkHeaderText.category.copyWith(
    fontWeight: FontWeight.w700,
    color: _TasteCardColors.wine,
  );

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: chosen
            ? TasteCardGuideColors.ticket
            : outlined
            ? Colors.transparent
            : PaperInk.chip,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        // The plain chip keeps the edge's room, so choosing moves nothing.
        border: Border.all(
          color: chosen
              ? _TasteCardColors.wine
              : outlined
              ? AppColors.textTertiary
              : PaperInk.chip,
          width: 1.5,
        ),
      ),
      child: Text(
        option.label,
        style: chosen
            ? _chosen
            : outlined
            ? _outlinedPlain
            : _plain,
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      selected: chosen,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: chip,
      ),
    );
  }
}

/// Opens the sheet the ways of drinking are chosen in (음용 방식, 음용
/// 온도). One glass may be drunk several ways, so each chip is touched on
/// or off; 완료 gives what is on, none for none, and null when closed.
Future<List<String>?> _showNoteServingSheet(
  BuildContext context,
  TasteCardNoteChoiceViewData choice,
  List<String> chosen,
) => showAppSheet<List<String>>(
  context: context,
  builder: (_) => _NoteChipSheet(
    field: choice.field,
    title: choice.label,
    description: choice.prompt,
    options: choice.options,
    chosen: chosen,
    several: true,
  ),
);

/// Opens the sheet 재음용 의사 is answered again in: the questionnaire's
/// own question and answers, of which one is kept. [chosen] is the answer
/// as it stands, an option id. Gives the option id chosen, or null when
/// the sheet is closed without 완료.
Future<String?> _showNoteRevisitSheet(
  BuildContext context,
  String? chosen,
) async {
  const prefix = 'revisit:';
  final kept = await showAppSheet<List<String>>(
    context: context,
    builder: (_) => _NoteChipSheet(
      field: 'revisit',
      // The questionnaire's own question and answers, as the record asks it.
      title: RevisitQuestion.recordTitle,
      options: <TasteCardNoteOptionViewData>[
        for (final (intent, label) in RevisitQuestion.recordOptions)
          TasteCardNoteOptionViewData(key: intent.name, label: label),
      ],
      chosen: <String>[
        if (chosen != null && chosen.startsWith(prefix))
          chosen.substring(prefix.length),
      ],
    ),
  );
  return switch (kept) {
    [final name] => '$prefix$name',
    _ => null,
  };
}

/// A sheet of chips under a name and what it asks, closed by 완료 with the
/// keys of the chips left on, in the sheet's order; closed any other way
/// it gives null and changes nothing. With [several] each chip is touched
/// on or off and none may be left on; otherwise touching one turns the
/// others off, and 완료 waits for one.
class _NoteChipSheet extends StatefulWidget {
  const _NoteChipSheet({
    required this.field,
    required this.title,
    required this.options,
    required this.chosen,
    this.description,
    this.several = false,
  });

  /// Names the chips' keys.
  final String field;
  final String title;
  final String? description;
  final List<TasteCardNoteOptionViewData> options;
  final List<String> chosen;
  final bool several;

  @override
  State<_NoteChipSheet> createState() => _NoteChipSheetState();
}

class _NoteChipSheetState extends State<_NoteChipSheet> {
  late final Set<String> _on = widget.chosen.toSet();

  void _touch(String key) => setState(() {
    if (!widget.several) {
      _on
        ..clear()
        ..add(key);
    } else if (!_on.remove(key)) {
      _on.add(key);
    }
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: appSheetPadding(context),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSheetHeading(title: widget.title, description: widget.description),
        const SizedBox(height: AppSpacing.xl),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final option in widget.options)
              _NoteOptionChip(
                key: _noteChipKey(widget.field, option.key),
                option: option,
                chosen: _on.contains(option.key),
                onTap: () => _touch(option.key),
                outlined: true,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        AppButton(
          key: ValueKey<String>('taste-card-note-${widget.field}-done'),
          label: '완료',
          onPressed: widget.several || _on.isNotEmpty
              ? () => Navigator.of(context).pop(<String>[
                  for (final option in widget.options)
                    if (_on.contains(option.key)) option.key,
                ])
              : null,
          variant: AppButtonVariant.accent,
          size: AppButtonSize.sheet,
        ),
      ],
    ),
  );
}

/// 재음용 의사 in the questionnaire's own words (있음, 애매해요, 없음): the
/// card's word for it read back to the answer it was written from, a
/// skipped question as 애매해요. A word no answer has stays as the card has
/// it.
String? _noteRevisitLabel(TasteCardNoteViewData note) {
  final word = note.revisit;
  if (word == null) return null;
  for (final MapEntry(key: id, value: said)
      in note.words?.revisit.entries ?? const <MapEntry<String, String>>[]) {
    if (said != word || !id.startsWith('revisit:')) continue;
    final intent = RevisitIntent.values
        .asNameMap()[id.substring('revisit:'.length)];
    if (intent != null) return RevisitQuestion.recordLabel(intent);
  }
  return word;
}
