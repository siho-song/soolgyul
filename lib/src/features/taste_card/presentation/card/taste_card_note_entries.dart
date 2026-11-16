part of '../taste_card_screen.dart';

// The choices the owner makes on the 테이스팅 노트 itself: the colour and
// the texture in 외관, and how it was drunk in the head. Each is stored as
// it is made. A choice of 외관 not made yet lies open with all its options;
// once made it shows the one chosen, which is touched to open it again.
// How it was drunk is a cell of the head that opens a sheet, where several
// ways may be kept.

/// The option of [choice] the owner chose; null with none chosen.
TasteCardNoteOptionViewData? _chosenOption(
  TasteCardNoteChoiceViewData choice,
  TastingNoteEditor entries,
) {
  final chosen = entries.valueOf(choice.field);
  for (final option in choice.options) {
    if (option.key == chosen) return option;
  }
  return null;
}

/// 외관: the look of the drink, one choice per group.
class _NoteAppearance extends StatelessWidget {
  const _NoteAppearance({
    required this.number,
    required this.appearance,
    required this.entries,
  });

  final String number;

  final TasteCardNoteAppearanceViewData appearance;
  final TastingNoteEditor entries;

  @override
  Widget build(BuildContext context) => _NoteSection(
    sectionKey: 'appearance',
    number: number,
    label: appearance.label,
    children: <Widget>[
      for (final (index, group) in appearance.groups.indexed) ...<Widget>[
        if (index > 0) const SizedBox(height: AppSpacing.s14),
        _NoteChoice(choice: group, entries: entries),
      ],
    ],
  );
}

/// One choice of 외관 under its name in small grey. With none made it lies
/// open: what asks for it, then every option, as chips or, for a colour or
/// a texture, as pictures; touching one keeps it and closes the choice.
/// With one made only that one shows, ending in a small arrow: touched, it
/// opens the choice again with the kept one marked, where touching another
/// keeps that instead and touching the kept one clears it.
class _NoteChoice extends StatefulWidget {
  const _NoteChoice({required this.choice, required this.entries});

  final TasteCardNoteChoiceViewData choice;
  final TastingNoteEditor entries;

  @override
  State<_NoteChoice> createState() => _NoteChoiceState();
}

class _NoteChoiceState extends State<_NoteChoice> {
  /// Whether the kept one was touched to choose again; kept on screen only.
  var _open = false;

  TasteCardNoteChoiceViewData get _choice => widget.choice;

  void _choose(TasteCardNoteOptionViewData option) {
    setState(() => _open = false);
    unawaited(widget.entries.choose(context, _choice.field, option.key));
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosenOption(_choice, widget.entries);
    // Null draws chips.
    final pictures = _NotePictures.of(_choice);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(_choice.label, style: _NoteText.choice),
        const SizedBox(height: AppSpacing.s6),
        if (chosen == null || _open)
          ..._picker(chosen, pictures)
        else
          _chosenView(chosen, pictures),
      ],
    );
  }

  List<Widget> _picker(
    TasteCardNoteOptionViewData? chosen,
    _NotePictures? pictures,
  ) => <Widget>[
    if (_choice.prompt case final prompt?) ...<Widget>[
      Text(prompt, style: _NoteText.muted),
      const SizedBox(height: AppSpacing.sm),
    ],
    if (pictures != null)
      _NotePalette(
        choice: _choice,
        pictures: pictures,
        chosen: chosen?.key,
        onChoose: _choose,
      )
    else
      Wrap(
        spacing: AppSpacing.s6,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final option in _choice.options)
            _NoteOptionChip(
              key: _noteOptionKey(_choice, option),
              option: option,
              chosen: option == chosen,
              onTap: () => _choose(option),
            ),
        ],
      ),
  ];

  /// The one chosen: its picture with its name beside it, or its chip, and
  /// the small arrow. Touched, it opens the choice again.
  Widget _chosenView(
    TasteCardNoteOptionViewData chosen,
    _NotePictures? pictures,
  ) => Semantics(
    button: true,
    child: GestureDetector(
      key: _noteOptionKey(_choice, chosen),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = true),
      child: Row(
        children: <Widget>[
          Flexible(
            child: pictures == null
                ? _NoteOptionChip(option: chosen, chosen: true)
                : _NoteChosenPick(
                    option: chosen,
                    painter: pictures.painters[_choice.options.indexOf(chosen)],
                    size: pictures.size,
                  ),
          ),
          const _NoteChevron(),
        ],
      ),
    ),
  );
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
/// edged and written in the card's wine. With [onTap] it is touched to
/// choose it.
class _NoteOptionChip extends StatelessWidget {
  const _NoteOptionChip({
    required this.option,
    required this.chosen,
    this.onTap,
    super.key,
  });

  final TasteCardNoteOptionViewData option;
  final bool chosen;
  final VoidCallback? onTap;

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
        color: chosen ? TasteCardGuideColors.ticket : PaperInk.chip,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        // The plain chip keeps the edge's room, so choosing moves nothing.
        border: Border.all(
          color: chosen ? _TasteCardColors.wine : PaperInk.chip,
          width: 1.5,
        ),
      ),
      child: Text(option.label, style: chosen ? _chosen : _plain),
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
/// or off; 완료 keeps what is on, and none clears the entry.
Future<void> _showNoteServingSheet(
  BuildContext context,
  TasteCardNoteChoiceViewData choice,
  TastingNoteEditor entries,
) async {
  final ways = await showAppSheet<List<String>>(
    context: context,
    builder: (_) => _NoteChipSheet(
      field: choice.field,
      title: choice.label,
      description: choice.prompt,
      options: choice.options,
      chosen: entries.servings,
      several: true,
    ),
  );
  // What went wrong is said on the page under the sheet.
  if (ways != null && context.mounted) {
    await entries.chooseServings(context, ways);
  }
}

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
      title: '재음용 의사',
      description: RevisitQuestion.title,
      options: <TasteCardNoteOptionViewData>[
        for (final (intent, label) in RevisitQuestion.options)
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
