part of '../taste_card_screen.dart';

// 테이스팅 노트: the drink's tasting sheet (시음 기록). The head names the
// drink and what the catalog knows of the bottle; under it one section
// holds 향, 맛 and 여운 as rows of a table, as the questionnaire's three
// steps ask them: the aromas of the nose as chips, the gauges of the palate
// and of the finish as the questionnaire's bars with the chosen step
// filled. A card answered under an older questionnaire holds
// 질감 in the flavours' place and its finish as marks alone. The
// sections are numbered from the head down. A part nobody answered keeps
// its place and says so. On the owner's saved app record the sheet is
// written on where it stands, with no mode to enter first: an answer is
// touched to answer its part again, and what the questions do not ask (the
// price and its place, how it was drunk, the closing line, the look, a
// memo in each section) is touched to enter it; a small arrow ends each
// such line. What the catalog says of the bottle is not touched. On any
// other card the sheet is only read and those slots are not drawn.

class _NoteSheet extends StatelessWidget {
  const _NoteSheet({
    required this.note,
    required this.product,
    required this.recordedAt,
    this.recordPrice,
    this.entries,
    this.recordMemo,
    this.answers,
    this.draft,
  });

  final TasteCardNoteViewData note;
  final TasteCardProductViewData product;
  final DateTime? recordedAt;

  /// The app record's price; null on a card with no app record.
  final RecordPriceEditor? recordPrice;

  /// What the owner entered on this sheet; null leaves the sheet read only.
  final TastingNoteEditor? entries;

  /// The record's one-line memo, written here as 총평.
  final RecordMemoEditor? recordMemo;

  /// The record's answers, corrected from this sheet; null leaves them as
  /// the card has them.
  final TasteCardAnswersEditor? answers;

  /// The form in edit mode; null while the note is only read.
  final _NoteDraft? draft;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Each is read after the card opens and changes as the owner writes.
    listenable: Listenable.merge(<Listenable>[
      ?recordPrice,
      ?entries,
      ?recordMemo,
      ?answers,
      ?draft,
    ]),
    builder: (context, _) => SingleChildScrollView(
      key: const ValueKey<String>('taste-card-note-scroll'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(
        top: AppSpacing.xl,
        bottom: AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _parts(context),
      ),
    ),
  );

  List<Widget> _parts(BuildContext context) {
    final entries = this.entries;
    final answers = entries == null ? null : this.answers;
    final draft = entries == null ? null : this.draft;
    // A part answered again is drawn from its answers until the card is
    // written again.
    final note = answers?.redrawn(this.note) ?? this.note;
    // In edit mode the answers are changed in place, with the
    // questionnaire's own picker and gauges.
    final flow = draft?.flow;
    final questions = answers?.questions;
    // A card answered on the gauges holds the flavours noticed in the
    // mouth; its gauges are written as the words the reader chose.
    final worded = note.flavor != null;
    var count = 0;
    String number() => '${++count}'.padLeft(2, '0');
    // The look chosen: the form's while it is written, the record's own
    // note where the reader may read it (a member's record), and otherwise
    // what the server sent with the card (a visitor's card, a card just
    // claimed), which is only read.
    String? chosenLook(TasteCardNoteChoiceViewData group) => draft != null
        ? (group.field == TastingNoteField.appearance
              ? draft.appearance
              : draft.texture)
        : entries != null
        ? entries.valueOf(group.field)
        : group.chosenKey;
    return <Widget>[
      _NoteHead(
        number: number(),
        note: note,
        product: product,
        recordedAt: recordedAt,
        recordPrice: recordPrice,
        entries: entries,
        recordMemo: entries == null ? null : recordMemo,
        draft: draft,
      ),
      _NoteSensesSection(
        number: number(),
        rows: <_NoteSenseRow>[
          // 색 and 점성 come first where the drink's look is noted: the one
          // chosen when read, every option in edit mode.
          if (note.appearance case final appearance?
              when entries == null || entries.settled)
            for (final group in appearance.groups)
              if (draft != null || chosenLook(group) != null)
                (
                  key: 'appearance-${group.field}',
                  label: group.label,
                  wide: false,
                  wrong: false,
                  content: _NoteChoice(
                    choice: group,
                    chosenKey: chosenLook(group),
                    onChoose: draft == null
                        ? null
                        : (key) => draft.setAppearance(group.field, key),
                  ),
                ),
          if ((draft, flow, questions) case (
            final draft?,
            final flow?,
            final questions?,
          )) ...<_NoteSenseRow>[
            (
              key: 'nose',
              label: '향',
              wide: true,
              wrong: draft.isWrong(_NoteDraft.senses),
              content: KeyedSubtree(
                key: draft.sensesKey,
                child: AromaPicker(
                  selected: flow.aromas(AromaStage.nose),
                  onToggle: (key) => draft.answer(
                    (flow) => flow.toggleAroma(AromaStage.nose, key),
                  ),
                  keyPrefix: 'aroma:nose:',
                  // The note shows every aroma of a tab, picked or not.
                  showAll: true,
                  menu: questions.aromaMenu,
                  label: (key) => questions.registry.aromaLabel(key) ?? key,
                ),
              ),
            ),
            for (final (key, label, gauges) in [
              ('palate', '맛', questions.gauges.palate),
              ('finish', '여운', questions.gauges.finish),
            ])
              if (gauges.isNotEmpty)
                (
                  key: key,
                  label: label,
                  wide: true,
                  wrong: draft.isWrong(_NoteDraft.senses),
                  content: SensoryGaugeList(
                    gauges: gauges,
                    levelOf: flow.level,
                    onChoose: (axis, level) =>
                        draft.answer((flow) => flow.chooseLevel(axis, level)),
                  ),
                ),
          ] else ...<_NoteSenseRow>[
            (
              key: 'nose',
              label: '향',
              wide: false,
              wrong: false,
              content: _NoteAromaGrid(groups: note.nose),
            ),
            (
              key: 'palate',
              label: '맛',
              wide: false,
              wrong: false,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _NoteBalanceRows(rows: note.balance, worded: worded),
                  // A card answered before the gauges also holds 질감.
                  if (note.flavor == null &&
                      note.texture.any(
                        (group) => group.marks.isNotEmpty,
                      )) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _NoteAromaChips(groups: note.texture),
                  ],
                ],
              ),
            ),
            (
              key: 'finish',
              label: '여운',
              wide: false,
              wrong: false,
              // A card answered before the finish had gauges of its own
              // holds every finish answer as a mark.
              content: switch (note.finishBalance) {
                final rows? => _NoteBalanceRows(rows: rows, worded: worded),
                null => _NoteAromaChips(groups: note.finish),
              },
            ),
          ],
        ],
      ),
    ];
  }
}

/// The owner's memo under what a section holds, only read.
List<Widget> _noteMemoPart({
  required String section,
  required String memo,
  String label = '메모',
}) => <Widget>[
  const SizedBox(height: AppSpacing.s14),
  _NoteMemoRow(
    key: ValueKey<String>('taste-card-note-memo-$section'),
    label: label,
    memo: memo,
  ),
];

/// One row of the senses section: its name and what the reader answered.
/// A [wide] row, in edit mode, puts its name over the questionnaire's own
/// inputs across the whole width; a [wrong] one is edged in red.
typedef _NoteSenseRow = ({
  String key,
  String label,
  Widget content,
  bool wide,
  bool wrong,
});

/// 상세 기록: 색 and 점성, then 향, 맛 and 여운, in one box, as a two-column table: a small grey name at
/// the left, what the reader answered at the right, a thin rule between
/// rows.
class _NoteSensesSection extends StatelessWidget {
  const _NoteSensesSection({required this.number, required this.rows});

  final String number;
  final List<_NoteSenseRow> rows;

  static const labelWidth = 44.0;

  Widget _row(_NoteSenseRow row, {required bool first}) {
    final label = Text(row.label, style: _NoteText.muted);
    Widget body = row.wide
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              label,
              const SizedBox(height: AppSpacing.md),
              row.content,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(width: labelWidth, child: label),
              Expanded(child: row.content),
            ],
          );
    if (row.wrong) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: AppColors.actionPrimary, width: 1.4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: body,
        ),
      );
    }
    return DecoratedBox(
      key: ValueKey<String>('taste-card-note-${row.key}'),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: _TasteCardColors.ticketLine)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: first ? 0 : AppSpacing.xxl,
          bottom: AppSpacing.xxl,
        ),
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _NoteSection(
    sectionKey: 'senses',
    number: number,
    label: '상세 기록',
    children: <Widget>[
      for (final (index, row) in rows.indexed) _row(row, first: index == 0),
    ],
  );
}

/// One part of the sheet in its own white box, under a heading like a reason
/// section's: its number, then its name.
class _NoteSection extends StatelessWidget {
  const _NoteSection({
    required this.sectionKey,
    required this.number,
    required this.label,
    required this.children,
  });

  final String sectionKey;
  final String number;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s14),
      child: _CardBox(
        key: ValueKey<String>('taste-card-note-$sectionKey'),
        children: <Widget>[
          _NumberedSectionLabel(number: number, label: label),
          const SizedBox(height: AppSpacing.xl),
          ...children,
        ],
      ),
    );
  }
}
