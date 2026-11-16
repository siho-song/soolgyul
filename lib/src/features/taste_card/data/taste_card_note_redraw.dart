import '../../../core/sensory/sensory_gauges.dart';
import '../../../core/sensory/sensory_meanings.dart';
import 'taste_card_note_view_data.dart';

/// [note] with the sections of the questions in [pending] (the chosen
/// option ids by question key) drawn from those answers, as the server will
/// write them: what the sheet shows between an answer being corrected and
/// the card being written again. A note without words is returned as it is.
///
/// The groups' names are the note's words; an aroma is named by
/// [aromaLabel] and a gauge's step by [gauges], the app's own.
TasteCardNoteViewData redrawNote(
  TasteCardNoteViewData note,
  Map<String, List<String>> pending, {
  required GaugeSet gauges,
  required String? Function(String aromaKey) aromaLabel,
}) {
  final words = note.words;
  if (words == null || pending.isEmpty) return note;
  final revisit = pending[SensoryQuestionKeys.revisit];
  final palateLevels = pending[SensoryQuestionKeys.palateLevel];
  final finishLevels = pending[SensoryQuestionKeys.finishLevel];
  List<TasteCardNoteGroupViewData>? aromas(String questionKey) =>
      switch (pending[questionKey]) {
        final answers? => _grouped(words, _aromaMarks(answers, aromaLabel)),
        null => null,
      };
  return TasteCardNoteViewData(
    originalName: note.originalName,
    facts: note.facts,
    nose: aromas(SensoryQuestionKeys.noseAroma) ?? note.nose,
    balance: palateLevels == null
        ? note.balance
        : _balance(note.balance, palateLevels, gauges.palate),
    texture: note.texture,
    flavor: aromas(SensoryQuestionKeys.palateAroma) ?? note.flavor,
    finishBalance: finishLevels == null
        ? note.finishBalance
        : _balance(
            note.finishBalance ?? const <TasteCardNoteBalanceViewData>[],
            finishLevels,
            gauges.finish,
          ),
    finish: aromas(SensoryQuestionKeys.finishAroma) ?? note.finish,
    revisit: revisit == null
        ? note.revisit
        : revisit.map((id) => words.revisit[id]).nonNulls.firstOrNull,
    appearance: note.appearance,
    serving: note.serving,
    words: words,
  );
}

/// [marks] under the sheet's groups, each by how it was taken.
List<TasteCardNoteGroupViewData> _grouped(
  TasteCardNoteWordsViewData words,
  List<TasteCardNoteMarkViewData> marks,
) => <TasteCardNoteGroupViewData>[
  for (final group in words.groups)
    TasteCardNoteGroupViewData(
      label: group.label,
      marks: <TasteCardNoteMarkViewData>[
        for (final mark in marks)
          if (group.felts.contains(mark.felt)) mark,
      ],
    ),
];

/// One mark per aroma picked, under the app's own name for it, in the order
/// picked.
List<TasteCardNoteMarkViewData> _aromaMarks(
  List<String> answers,
  String? Function(String aromaKey) aromaLabel,
) => <TasteCardNoteMarkViewData>[
  for (final option in answers.map(SensoryAnswerOption.parse).nonNulls)
    if (option.item.stage != null)
      if (aromaLabel(option.item.key) case final label?)
        TasteCardNoteMarkViewData(
          label: label,
          felt: option.burden
              ? TasteCardNoteFelt.burden
              : TasteCardNoteFelt.liked,
        ),
];

/// The steps chosen on [asked], by axis.
Map<String, SensoryAnswerOption> _chosen(
  List<String> answers,
  List<SensoryGauge> asked,
) => <String, SensoryAnswerOption>{
  for (final option in answers.map(SensoryAnswerOption.parse).nonNulls)
    if (option.level != null &&
        asked.any((gauge) => gauge.axis == option.item.key))
      option.item.key: option,
};

/// How a step was taken, as the server reads it: a burden at a high step
/// is less of it wanted, at a low step more. An axis that runs between two
/// characters is no strength, so there a burden is only that.
TasteCardNoteFelt _gaugeFelt(SensoryGauge gauge, SensoryAnswerOption option) {
  if (!option.burden) return TasteCardNoteFelt.liked;
  final level = option.level!;
  if (gauge.ends != null || level == 3) return TasteCardNoteFelt.burden;
  return level > 3 ? TasteCardNoteFelt.less : TasteCardNoteFelt.more;
}

/// The rows of 맛 밸런스 or 여운 밸런스 with the step the reader now chooses on
/// each gauge: a row keeps its name, the bottle's level and its word. A
/// gauge answered with no row gets one without the bottle's level, in the
/// gauges' order; a row with neither goes. Rows of anything else stay after
/// them, and rows stored without their axis cannot be told apart and stay
/// as they are.
List<TasteCardNoteBalanceViewData> _balance(
  List<TasteCardNoteBalanceViewData> rows,
  List<String> answers,
  List<SensoryGauge> asked,
) {
  if (rows.any((row) => row.key == null)) return rows;
  final chosen = _chosen(answers, asked);
  return <TasteCardNoteBalanceViewData>[
    for (final gauge in asked)
      if ((
            rows.where((row) => row.key == gauge.axis).firstOrNull,
            chosen[gauge.axis],
          )
          case (final row, final option)
          when row?.mark != null || option != null)
        TasteCardNoteBalanceViewData(
          key: gauge.axis,
          label: row?.label ?? gauge.label,
          mark: row?.mark,
          word: row?.word,
          felt: option == null ? null : _gaugeFelt(gauge, option),
          said: option == null ? null : gauge.levelAt(option.level!).term,
          level: option?.level,
          ends: row?.ends ?? gauge.ends,
        ),
    for (final row in rows)
      if (!asked.any((gauge) => gauge.axis == row.key)) row,
  ];
}
