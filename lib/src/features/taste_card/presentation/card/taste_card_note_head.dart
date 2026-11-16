part of '../taste_card_screen.dart';

// The head of the 테이스팅 노트, 기본 정보: the card's own drink header, then
// what else the catalog knows of the bottle and what the record says of the
// drinking (구매 정보, how it was drunk, 재음용 의사) as small cells two to a
// line, then 총평.

/// The catalog photo when the drink has one, and beside it the drink, its
/// name in its own language in grey, and the line the card's header writes
/// (레드 와인 · 14% · 2026.11.15). Under a line, the bottle's other facts,
/// the record's 구매 정보 (the price and where it was paid, in one cell),
/// how it was drunk, and 재음용 의사. Under another line, 총평: the owner's
/// closing memo.
///
/// On a sheet the owner writes on, each of these is touched to enter or
/// change it and ends in a small arrow: 구매 정보 and the ways of drinking
/// open their sheets and offer to be added while empty, 재음용 의사 opens
/// its question again, and 총평 its memo. The catalog's facts, the names
/// and the photo are not touched.
class _NoteHead extends StatelessWidget {
  const _NoteHead({
    required this.number,
    required this.note,
    required this.product,
    required this.recordedAt,
    required this.recordPrice,
    required this.entries,
    required this.recordMemo,
    required this.onRevisit,
  });

  final String number;
  final TasteCardNoteViewData note;
  final TasteCardProductViewData product;
  final DateTime? recordedAt;
  final RecordPriceEditor? recordPrice;

  /// What the owner entered on the sheet; null on a sheet only read.
  final TastingNoteEditor? entries;

  /// The record's one-line memo, 총평 here; null on a sheet only read.
  final RecordMemoEditor? recordMemo;

  /// Opens the 재음용 의사 question again; null where it cannot be
  /// answered again.
  final VoidCallback? onRevisit;

  bool get _editable => entries != null;

  /// Larger than on the card: the sheet's head is about the bottle.
  static const _photoSize = 68.0;

  _NoteFactCell? _purchaseCell(BuildContext context) {
    final editor = recordPrice;
    final price = editor?.price;
    // Before the price has been read there is no cell, so a stored price
    // never shows as one to add.
    if (editor == null || (price == null && !(_editable && editor.settled))) {
      return null;
    }
    return _NoteFactCell(
      key: const ValueKey<String>('taste-card-note-price'),
      label: '구매 정보',
      value: price?.infoLine ?? '',
      onTap: _editable ? () => unawaited(editor.edit(context)) : null,
    );
  }

  /// 음용 방식 · 음용 온도: how it was drunk, which comes before the nose
  /// and the palate. Before the entries have been read there is no cell.
  _NoteFactCell? _servingCell(BuildContext context) {
    final entries = this.entries;
    final serving = note.serving;
    if (entries == null || serving == null || !entries.settled) return null;
    return _NoteFactCell(
      key: const ValueKey<String>('taste-card-note-serving'),
      label: serving.label,
      // 니트 · 하이볼, in the sheet's order.
      value: <String>[
        for (final option in serving.options)
          if (entries.servings.contains(option.key)) option.chosenLabel,
      ].join(' · '),
      onTap: () => unawaited(_showNoteServingSheet(context, serving, entries)),
    );
  }

  /// 재음용 의사: the reader's answer. Where it can be answered again the
  /// cell stays even with no word for the answer, and offers to add one.
  _NoteFactCell? _revisitCell() {
    final revisit = note.revisit;
    if (revisit == null && onRevisit == null) return null;
    return _NoteFactCell(
      key: const ValueKey<String>('taste-card-note-revisit'),
      label: '재음용 의사',
      value: revisit ?? '',
      onTap: onRevisit,
    );
  }

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
    final memo = recordMemo;
    final cells = <_NoteFactCell>[
      for (final fact in note.facts)
        _NoteFactCell(label: fact.label, value: fact.value),
      ?_purchaseCell(context),
      ?_servingCell(context),
      ?_revisitCell(),
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
              ],
            ),
          ),
        ],
      ),
      if (cells.isNotEmpty) ...<Widget>[
        const _ParagraphRule(),
        _NoteFactGrid(cells: cells),
      ],
      // Nothing until the memo has been read, so a stored one never shows
      // as one to add.
      if ((memo, memo?.memo) case (final memo?, final text?))
        ..._noteMemoPart(
          section: 'overall',
          label: '총평',
          memo: text,
          onEdit: () => unawaited(memo.edit(context, title: '총평')),
        ),
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
              width: _fitsOneLine(context, cell.shown, half - cell.arrowRoom)
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

/// One fact: its name in small grey over its value. With [onTap] the cell
/// is touched to enter or change the value, which a small arrow after it
/// says, and one with no value yet offers to add it.
class _NoteFactCell extends StatelessWidget {
  const _NoteFactCell({
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  bool get _isEmpty => value.isEmpty && onTap != null;

  /// What the cell writes under its name.
  String get shown => _isEmpty ? _noteAddWording : value;

  /// The width the arrow takes of the value's line.
  double get arrowRoom => onTap == null ? 0 : _NoteChevron.room;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    final written = Text(
      shown,
      style: _isEmpty ? _DrinkHeaderText.addPrice : _NoteText.value,
    );
    final cell = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: _NoteText.muted),
        if (onTap == null)
          written
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: written),
              const _NoteChevron(),
            ],
          ),
      ],
    );
    if (onTap == null) return cell;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: cell,
      ),
    );
  }
}
