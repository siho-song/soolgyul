part of '../taste_card_screen.dart';

// The head of the 테이스팅 노트, 기본 정보: the card's own drink header, then
// what else the catalog knows of the bottle and what the record says of the
// drinking as small cells two to a line, the owner's form, then 총평.

/// The catalog photo when the drink has one, and beside it the drink, its
/// name in its own language in grey, and the line the card's header writes
/// (레드 와인 · 14% · 2026.11.15). Under a line, the bottle's other facts,
/// how it was drunk and 재음용 의사; on a sheet only read, the price and
/// where it was bought when written. Under another line, 총평.
///
/// On a sheet the owner writes on, the ways of drinking open their sheet,
/// 재음용 의사 its question and 총평 its memo; under the cells a form takes
/// when it was drunk and bought, with whom and where, the pairing, the
/// price and where it was bought. The catalog's facts are not touched.
class _NoteHead extends StatelessWidget {
  const _NoteHead({
    required this.number,
    required this.note,
    required this.product,
    required this.recordedAt,
    required this.recordPrice,
    required this.entries,
    required this.recordMemo,
    required this.draft,
  });

  final String number;
  final TasteCardNoteViewData note;
  final TasteCardProductViewData product;
  final DateTime? recordedAt;
  final RecordPriceEditor? recordPrice;

  /// What the owner entered on the sheet; null on another's card.
  final TastingNoteEditor? entries;

  /// The record's 총평; null on another's card.
  final RecordMemoEditor? recordMemo;

  /// The form in edit mode; null while the note is only read.
  final _NoteDraft? draft;

  /// Larger than on the card: the sheet's head is about the bottle.
  static const _photoSize = 68.0;

  /// What the owner wrote, as cells when the note is read; each only when
  /// written.
  List<_NoteFactCell> _writtenCells() {
    final entries = this.entries;
    if (entries == null || !entries.settled) return const <_NoteFactCell>[];
    _NoteFactCell? day(String field, String label) =>
        switch (TastingNoteField.dayOf(entries.valueOf(field))) {
          final day? => _NoteFactCell(
            key: ValueKey<String>('taste-card-note-$field'),
            label: label,
            value: dotDay(day),
          ),
          null => null,
        };
    _NoteFactCell? words(String field, String label) =>
        switch (entries.valueOf(field)) {
          final text? => _NoteFactCell(
            key: ValueKey<String>('taste-card-note-$field'),
            label: label,
            value: text,
            wide: true,
          ),
          null => null,
        };
    final serving = note.serving;
    final ways = serving == null
        ? ''
        : <String>[
            for (final option in serving.options)
              if (entries.servings.contains(option.key)) option.chosenLabel,
          ].join(' · ');
    // As the form has them: two to a line, then the long ones across it.
    return <_NoteFactCell>[
      ?day(TastingNoteField.purchasedOn, '구입 날짜'),
      ?_revisitCell(),
      if (recordPrice?.price?.amount case final won?)
        _NoteFactCell(label: '가격', value: '${formatWon(won)}원'),
      if (recordPrice?.price?.place case final place?)
        _NoteFactCell(label: '구입처', value: place),
      if (ways.isNotEmpty)
        _NoteFactCell(
          key: const ValueKey<String>('taste-card-note-serving'),
          label: serving!.label,
          value: ways,
          wide: true,
        ),
      ?words(TastingNoteField.companionPlace, '누구와 어디서'),
      ?words(TastingNoteField.pairing, '페어링'),
    ];
  }

  _NoteFactCell? _revisitCell() => switch (_noteRevisitLabel(note)) {
    final revisit? => _NoteFactCell(
      key: const ValueKey<String>('taste-card-note-revisit'),
      label: '재음용 의사',
      value: revisit,
    ),
    null => null,
  };

  @override
  Widget build(BuildContext context) => _NoteSection(
    sectionKey: 'head',
    number: number,
    label: '기본 정보',
    children: _parts(context),
  );

  List<Widget> _parts(BuildContext context) {
    final photoUrl = _catalogPhotoUrl(product);
    final line = _drinkFactsLine(product, recordedAt);
    final draft = this.draft;
    final memo = recordMemo?.memo;
    // The bottle's facts, then under a line of their own what the member
    // wrote.
    final facts = <_NoteFactCell>[
      for (final fact in note.facts)
        _NoteFactCell(label: fact.label, value: fact.value),
    ];
    final written = <_NoteFactCell>[
      if (draft == null) ...<_NoteFactCell>[
        // Another's card shows the price as the card has it.
        if (entries == null) ...<_NoteFactCell>[
          if (recordPrice?.price?.amount case final won?)
            _NoteFactCell(label: '가격', value: '${formatWon(won)}원'),
          ?_revisitCell(),
        ] else
          ..._writtenCells(),
      ],
    ];
    return <Widget>[
      Row(
        children: <Widget>[
          if (photoUrl != null) ...<Widget>[
            DrinkResultPhoto(url: photoUrl, selected: false, size: _photoSize),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(product.drinkNameSnapshot, style: _DrinkHeaderText.name),
                if (note.originalName case final original?)
                  Text(original, style: _NoteText.muted),
                if (line.isNotEmpty)
                  Text(line, style: _DrinkHeaderText.category),
                // The member's stars, when the note is read and has some.
                if (draft == null)
                  if (double.tryParse(
                        entries?.valueOf(TastingNoteField.rating) ?? '',
                      )
                      case final stars?)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: _NoteStars(rating: stars, size: AppSizes.iconSm),
                    ),
              ],
            ),
          ),
        ],
      ),
      for (final cells in [facts, written])
        if (cells.isNotEmpty) ...<Widget>[
          const _ParagraphRule(),
          _NoteFactGrid(cells: cells),
        ],
      if (draft != null) ...<Widget>[
        const _ParagraphRule(),
        _NoteEditForm(
          draft: draft,
          serving: note.serving,
          revisit: _noteRevisitLabel(note),
        ),
      ] else if (memo != null && memo.isNotEmpty)
        ..._noteMemoPart(section: 'overall', label: '총평', memo: memo),
    ];
  }
}

/// The cells two to a line. One whose value is too long for half the line
/// takes the whole line, and wraps there if it must.
class _NoteFactGrid extends StatelessWidget {
  const _NoteFactGrid({required this.cells});

  final List<_NoteFactCell> cells;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final whole = constraints.maxWidth;
      final half = ((whole - AppSpacing.lg) / 2).floorToDouble();
      return Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        children: <Widget>[
          for (final cell in cells)
            SizedBox(
              width: !cell.wide && _fitsOneLine(context, cell.shown, half)
                  ? half
                  : whole,
              child: cell,
            ),
        ],
      );
    },
  );

  /// Whether [text] in a value's style stays on one line of [width].
  static bool _fitsOneLine(BuildContext context, String text, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(_NoteText.value),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final fits = painter.width <= width;
    painter.dispose();
    return fits;
  }
}

/// One fact: its name in small grey over its value, only read.
class _NoteFactCell extends StatelessWidget {
  const _NoteFactCell({
    required this.label,
    required this.value,
    this.wide = false,
    super.key,
  });

  final String label;
  final String value;

  /// Whether the cell takes the whole line, as a long one does.
  final bool wide;

  /// What the cell writes under its name.
  String get shown => value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: _NoteText.muted),
      Text(value, style: _NoteText.value),
    ],
  );
}
