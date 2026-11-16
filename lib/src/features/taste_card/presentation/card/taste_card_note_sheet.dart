part of '../taste_card_screen.dart';

// 테이스팅 노트: the drink's tasting sheet (시음 기록). The head names the
// drink and what the catalog knows of the bottle; under it 향, 맛과 질감
// and 마무리와 여운 hold what the reader answered, as the questionnaire's
// three steps ask it: the aromas of the nose, the gauges of the palate and
// the flavours noticed in the mouth, the gauges of the finish and the
// flavours left after swallowing. A gauge is the reader's answer in words:
// its name and the term chosen, with no bar of the bottle's own level. The aromas stand in the server's groups
// by how each was taken. A card answered under an older questionnaire holds
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Each is read after the card opens and changes as the owner writes.
    listenable: Listenable.merge(<Listenable>[
      ?recordPrice,
      ?entries,
      ?recordMemo,
      ?answers,
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
    // A part answered again is drawn from its answers until the card is
    // written again.
    final note = answers?.redrawn(this.note) ?? this.note;
    VoidCallback? opens(SensoryPart part) => answers == null
        ? null
        : () => unawaited(answers.edit(context, part, note: this.note));
    final onRevisit = answers == null
        ? null
        : () => unawaited(
            answers.editRevisit(
              context,
              note: this.note,
              choose: (chosen) => _showNoteRevisitSheet(context, chosen),
            ),
          );
    // A card answered on the gauges holds the flavours noticed in the
    // mouth; its gauges are written as the words the reader chose.
    final worded = note.flavor != null;
    var count = 0;
    String number() => '${++count}'.padLeft(2, '0');
    return <Widget>[
      _NoteHead(
        number: number(),
        note: note,
        product: product,
        recordedAt: recordedAt,
        recordPrice: recordPrice,
        entries: entries,
        recordMemo: entries == null ? null : recordMemo,
        onRevisit: onRevisit,
      ),
      if ((entries, note.appearance) case (final entries?, final appearance?))
        _NoteAppearance(
          number: number(),
          appearance: appearance,
          entries: entries,
        ),
      _NoteAnswerSection(
        sectionKey: 'nose',
        number: number(),
        label: '향(Aroma)',
        onEdit: opens(SensoryPart.aroma),
        answers: <Widget>[
          _NoteMarkGroups(groups: note.nose, answerable: answers != null),
        ],
        memo: _memo(
          context,
          'nose',
          TastingNoteField.aromaMemo,
          '향 메모',
          '예) 잔을 돌리니 바닐라 향이 더 올라왔어요.',
        ),
      ),
      _NoteAnswerSection(
        sectionKey: 'palate',
        number: number(),
        label: '맛과 질감(Palate)',
        onEdit: opens(SensoryPart.palate),
        answers: <Widget>[
          const Text('맛 밸런스', style: _NoteText.part),
          const SizedBox(height: AppSpacing.s10),
          _NoteBalanceRows(
            rows: note.balance,
            worded: worded,
            answerable: answers != null,
          ),
          const _ParagraphRule(),
          // A card answered before the gauges holds 질감 where one answered
          // since holds the flavours noticed in the mouth.
          if (note.flavor case final flavor?) ...<Widget>[
            const Text('입안에서 느껴진 풍미', style: _NoteText.part),
            const SizedBox(height: AppSpacing.s10),
            _NoteMarkGroups(groups: flavor, answerable: answers != null),
          ] else ...<Widget>[
            const Text('질감', style: _NoteText.part),
            const SizedBox(height: AppSpacing.s10),
            _NoteMarkGroups(groups: note.texture, answerable: answers != null),
          ],
        ],
        memo: _memo(
          context,
          'palate',
          TastingNoteField.palateMemo,
          '맛·질감 메모',
          '예) 처음엔 달았는데 끝은 쌉쌀했어요.',
        ),
      ),
      _NoteAnswerSection(
        sectionKey: 'finish',
        number: number(),
        label: '마무리와 여운(Finish)',
        onEdit: opens(SensoryPart.finish),
        answers: <Widget>[
          // A card answered before the finish had gauges of its own holds
          // every finish answer as a mark.
          if (note.finishBalance case final rows?) ...<Widget>[
            const Text('여운 밸런스', style: _NoteText.part),
            const SizedBox(height: AppSpacing.s10),
            _NoteBalanceRows(
              rows: rows,
              worded: worded,
              answerable: answers != null,
            ),
            const _ParagraphRule(),
            const Text('삼킨 뒤 느껴진 풍미', style: _NoteText.part),
            const SizedBox(height: AppSpacing.s10),
          ],
          _NoteMarkGroups(groups: note.finish, answerable: answers != null),
        ],
        memo: _memo(
          context,
          'finish',
          TastingNoteField.finishMemo,
          '마무리·여운 메모',
          '예) 삼킨 뒤에도 과일 향이 오래 남았어요.',
        ),
      ),
    ];
  }

  /// The memo of the section named [section], kept under [field] and
  /// written in a sheet named [title] whose empty field shows [hint];
  /// nothing on a sheet only read, and before the entries have been read,
  /// so a stored memo never shows as one to add.
  List<Widget> _memo(
    BuildContext context,
    String section,
    String field,
    String title,
    String hint,
  ) {
    final entries = this.entries;
    if (entries == null || !entries.settled) return const <Widget>[];
    return _noteMemoPart(
      section: section,
      memo: entries.memoOf(field),
      onEdit: () => unawaited(
        entries.editMemo(context, field: field, title: title, hintText: hint),
      ),
    );
  }
}

/// The owner's memo under what a section holds: touched to write or change
/// it, and one not written yet offers to.
List<Widget> _noteMemoPart({
  required String section,
  required String memo,
  required VoidCallback onEdit,
  String label = '메모',
}) => <Widget>[
  const SizedBox(height: AppSpacing.s14),
  _NoteMemoRow(
    key: ValueKey<String>('taste-card-note-memo-$section'),
    label: label,
    memo: memo,
    onTap: onEdit,
  ),
];

/// 향, 맛과 질감 or 마무리와 여운: what the reader answered, then the
/// owner's memo. With [onEdit] the heading, which then ends in a small
/// arrow, and the answers themselves are touched to answer the part again,
/// in the question's own sheet.
class _NoteAnswerSection extends StatelessWidget {
  const _NoteAnswerSection({
    required this.sectionKey,
    required this.number,
    required this.label,
    required this.answers,
    required this.memo,
    this.onEdit,
  });

  final String sectionKey;
  final String number;
  final String label;

  /// What the reader answered, as the section draws it.
  final List<Widget> answers;

  /// The memo line under the answers; empty for none.
  final List<Widget> memo;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final onEdit = this.onEdit;
    final answered = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: answers,
    );
    return _NoteSection(
      sectionKey: sectionKey,
      number: number,
      label: label,
      onOpen: onEdit,
      children: <Widget>[
        if (onEdit == null)
          answered
        else
          Semantics(
            button: true,
            child: GestureDetector(
              key: ValueKey<String>('taste-card-note-answers-$sectionKey'),
              behavior: HitTestBehavior.opaque,
              onTap: onEdit,
              child: answered,
            ),
          ),
        ...memo,
      ],
    );
  }
}

/// One part of the sheet on its own paper, under a heading like a reason
/// section's: its number, then its name. With [onOpen] the heading ends in
/// a small arrow at the box's right edge and is touched to change what the
/// part holds.
class _NoteSection extends StatelessWidget {
  const _NoteSection({
    required this.sectionKey,
    required this.number,
    required this.label,
    required this.children,
    this.onOpen,
  });

  final String sectionKey;
  final String number;
  final String label;
  final List<Widget> children;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final heading = _NumberedSectionLabel(number: number, label: label);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s14),
      child: _CardBox(
        key: ValueKey<String>('taste-card-note-$sectionKey'),
        children: <Widget>[
          if (onOpen case final onOpen?)
            Semantics(
              button: true,
              child: GestureDetector(
                key: ValueKey<String>('taste-card-note-edit-$sectionKey'),
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: Row(
                  children: <Widget>[
                    Expanded(child: heading),
                    const _NoteChevron(),
                  ],
                ),
              ),
            )
          else
            heading,
          const SizedBox(height: AppSpacing.xl),
          ...children,
        ],
      ),
    );
  }
}
