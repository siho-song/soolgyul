import 'taste_card_note_view_data.dart';

/// The tastes a reader reacts to, in the order of their rows, which every
/// kind's sheet begins with.
const _tastes = <String>['sweetness', 'acidity', 'bitterness'];

/// [note] with the sections of the questions in [pending] (the chosen
/// option ids by question key) drawn from those answers and the note's
/// words, as the server will write them: what the sheet shows between an
/// answer being corrected and the card being written again. A note without
/// words is returned as it is.
///
/// [labelOf] gives the app's own name for an answer option, which an aroma
/// and a taste with no row of its own are written with.
TasteCardNoteViewData redrawNote(
  TasteCardNoteViewData note,
  Map<String, List<String>> pending, {
  required String? Function(String optionId) labelOf,
}) {
  final words = note.words;
  if (words == null || pending.isEmpty) return note;
  final aroma = pending['sensory_aroma'];
  final taste = pending['sensory_taste'];
  final mouthfeel = pending['sensory_mouthfeel'];
  final finish = pending['sensory_finish'];
  final revisit = pending['sensory_revisit'];
  return TasteCardNoteViewData(
    originalName: note.originalName,
    facts: note.facts,
    nose: aroma == null
        ? note.nose
        : _grouped(words, _aromaMarks(aroma, labelOf)),
    balance: taste == null
        ? note.balance
        : _balance(note.balance, taste, words, labelOf),
    texture: mouthfeel == null
        ? note.texture
        : _grouped(words, _textureMarks(mouthfeel, words)),
    finish: finish == null
        ? note.finish
        : _grouped(words, <TasteCardNoteMarkViewData>[
            for (final id in _listed(finish, words)) ?words.marks[id],
          ]),
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

/// [answers] in the order the sheet lists their marks; one the words do not
/// place comes last.
List<String> _listed(List<String> answers, TasteCardNoteWordsViewData words) {
  int place(String id) {
    final index = words.order.indexOf(id);
    return index < 0 ? words.order.length : index;
  }

  return answers.toList()..sort((a, b) => place(a).compareTo(place(b)));
}

/// One mark per aroma named, under the app's own name for it: a burden, or
/// liked, as one only named reads too. The server lists aromas by their
/// keys.
List<TasteCardNoteMarkViewData> _aromaMarks(
  List<String> answers,
  String? Function(String optionId) labelOf,
) {
  const notice = 'notice:aroma:';
  return <TasteCardNoteMarkViewData>[
    for (final id in answers.toList()..sort())
      if (id.startsWith(notice))
        if (labelOf(id) case final label?)
          TasteCardNoteMarkViewData(
            label: label,
            felt: switch (id.substring(notice.length)) {
              final key when answers.contains('reaction:aroma:$key:disliked') =>
                TasteCardNoteFelt.burden,
              _ => TasteCardNoteFelt.liked,
            },
          ),
  ];
}

/// One mark per sensation noticed: that of how it was taken when the
/// reader said, else that of noticing it.
List<TasteCardNoteMarkViewData> _textureMarks(
  List<String> answers,
  TasteCardNoteWordsViewData words,
) {
  const notice = 'notice:mouthfeel:';
  return <TasteCardNoteMarkViewData>[
    for (final id in _listed(answers, words))
      if (id.startsWith(notice))
        ?(words.marks[_firstOf(
              answers,
              'reaction:mouthfeel:${id.substring(notice.length)}:',
            )] ??
            words.marks[id]),
  ];
}

/// The rows of 맛 밸런스 with what the reader now says of each taste: a
/// row keeps its name, its level and its word. A taste with a remark and
/// no row gets one without a gauge, in the tastes' order; a row with
/// neither a gauge nor a remark goes. Rows stored without their axis cannot
/// be told apart and stay as they are.
List<TasteCardNoteBalanceViewData> _balance(
  List<TasteCardNoteBalanceViewData> rows,
  List<String> answers,
  TasteCardNoteWordsViewData words,
  String? Function(String optionId) labelOf,
) {
  if (rows.any((row) => row.key == null)) return rows;
  // The first reason the words know, else the reaction itself; null for a
  // taste with no reaction.
  TasteCardNoteSaidViewData? saidOf(String taste) {
    final reaction = _firstOf(answers, 'reaction:taste:$taste:');
    if (reaction == null) return null;
    for (final id in answers) {
      if (!id.startsWith('reason:taste:$taste:')) continue;
      if (words.taste[id] case final said?) return said;
    }
    return words.taste[reaction];
  }

  // The tastes lead the rows, in their own order.
  return <TasteCardNoteBalanceViewData>[
    for (final taste in _tastes)
      if ((rows.where((row) => row.key == taste).firstOrNull, saidOf(taste))
          case (final row, final said) when row?.mark != null || said != null)
        if (row?.label ?? labelOf('reaction:taste:$taste:liked')
            case final label?)
          TasteCardNoteBalanceViewData(
            key: taste,
            label: label,
            mark: row?.mark,
            word: row?.word,
            felt: said?.felt,
            said: said?.said,
          ),
    for (final row in rows)
      if (!_tastes.contains(row.key)) row,
  ];
}

/// The first of [answers] that starts with [prefix]; null with none.
String? _firstOf(List<String> answers, String prefix) {
  for (final id in answers) {
    if (id.startsWith(prefix)) return id;
  }
  return null;
}
