import 'package:flutter/foundation.dart';

/// 테이스팅 노트: the drink's tasting sheet, filled with what the catalog
/// knows of the bottle and what the reader answered. A part nobody answered
/// is an empty list.
@immutable
class TasteCardNoteViewData {
  const TasteCardNoteViewData({
    this.originalName,
    this.facts = const <TasteCardNoteFactViewData>[],
    this.nose = const <TasteCardNoteGroupViewData>[],
    this.balance = const <TasteCardNoteBalanceViewData>[],
    this.texture = const <TasteCardNoteGroupViewData>[],
    this.flavor,
    this.finishBalance,
    this.finish = const <TasteCardNoteGroupViewData>[],
    this.revisit,
    this.appearance,
    this.serving,
    this.words,
  });

  /// The drink's name in its own language; null when the catalog has none.
  final String? originalName;

  /// The bottle's own facts at the head of the sheet, past the kind and
  /// the ABV the card's product carries: 생산자, 품종, 산지.
  final List<TasteCardNoteFactViewData> facts;

  /// 향: the aromas, in the server's groups by how each was taken.
  final List<TasteCardNoteGroupViewData> nose;

  /// 맛 밸런스: one row per taste, or per gauge the reader was asked.
  final List<TasteCardNoteBalanceViewData> balance;

  /// 질감, grouped likewise. Only a card answered before the gauges has
  /// any; the gauges took its place.
  final List<TasteCardNoteGroupViewData> texture;

  /// 입안에서 느껴진 풍미: the aromas noticed in the mouth, grouped likewise;
  /// null on a card stored before they were asked, which shows 질감 in
  /// their place.
  final List<TasteCardNoteGroupViewData>? flavor;

  /// 여운 밸런스: one row per gauge of the finish, like [balance]; null on a
  /// card stored before the finish had rows, whose [finish] holds them as
  /// marks.
  final List<TasteCardNoteBalanceViewData>? finishBalance;

  /// 삼킨 뒤 느껴진 풍미: the aromas left after swallowing, grouped likewise.
  /// On a card without [finishBalance], every finish answer as a mark.
  final List<TasteCardNoteGroupViewData> finish;

  /// 재음용 의사: the reader's answer; null when there is none.
  final String? revisit;

  /// 외관: what the reader may say of the drink's look; null for a kind of
  /// drink whose look is not noted, and on a card stored before it.
  final TasteCardNoteAppearanceViewData? appearance;

  /// 음용 방식: how the reader may say it was drunk; null likewise.
  final TasteCardNoteChoiceViewData? serving;

  /// The words a section is redrawn with once its owner answers it again;
  /// null on a card served without them, whose answers cannot be corrected.
  final TasteCardNoteWordsViewData? words;
}

/// What the sheet needs to redraw a section its owner has just answered
/// again, before the server writes the card again: the server's names for
/// the groups and for 재음용 의사. An aroma's name and a gauge's words are
/// the app's own.
@immutable
class TasteCardNoteWordsViewData {
  const TasteCardNoteWordsViewData({
    required this.groups,
    this.revisit = const <String, String>{},
  });

  /// The groups a section's marks stand under, in the sheet's order.
  final List<TasteCardNoteWordGroupViewData> groups;

  /// 재음용 의사, by the answer.
  final Map<String, String> revisit;
}

/// A group of the sheet: its name, and the ways of taking a thing whose
/// marks stand under it.
@immutable
class TasteCardNoteWordGroupViewData {
  const TasteCardNoteWordGroupViewData({
    required this.label,
    required this.felts,
  }) : assert(label != '');

  final String label;
  final Set<TasteCardNoteFelt> felts;
}

/// 외관 · 색상: the look of the drink, one choice per group (색, 점성).
@immutable
class TasteCardNoteAppearanceViewData {
  const TasteCardNoteAppearanceViewData({
    required this.label,
    required this.groups,
  }) : assert(label != '');

  final String label;
  final List<TasteCardNoteChoiceViewData> groups;
}

/// One thing the reader may choose on the sheet, of which one option is
/// kept: 색, then 루비 · 가넷.
@immutable
class TasteCardNoteChoiceViewData {
  const TasteCardNoteChoiceViewData({
    required this.field,
    required this.label,
    required this.options,
    this.prompt,
    this.chosenKey,
  }) : assert(field != ''),
       assert(label != '');

  /// The tasting note's field the choice is saved under: appearance,
  /// appearance_texture, serving.
  final String field;
  final String label;

  /// What asks for the choice while none is made: 색상을 선택해주세요; null
  /// on a card stored before choices carried one.
  final String? prompt;
  final List<TasteCardNoteOptionViewData> options;

  /// The option the record's note held when the server sent the card, one
  /// of [options]; null for none. It is what a note shows where the reader
  /// cannot read the record's note itself: a visitor's card, and a card
  /// just claimed. A member's own record reads its note, which may have
  /// been written again since.
  final String? chosenKey;
}

/// One option of a choice: its stored key, its name, and for a colour the
/// colour itself, or the name of the small drawing that shows it.
@immutable
class TasteCardNoteOptionViewData {
  const TasteCardNoteOptionViewData({
    required this.key,
    required this.label,
    this.swatch,
    this.icon,
    this.short,
  }) : assert(key != ''),
       assert(label != '');

  final String key;
  final String label;

  /// The colour as an opaque ARGB value; null when the option has none.
  final int? swatch;

  /// The drawing that shows the option (sediment_low, legs_heavy); null
  /// when it has none. One this app cannot draw is shown as a chip.
  final String? icon;

  /// The term alone (니트 for 원액 그대로(니트)); null when the label is it.
  final String? short;

  /// What the sheet writes once the option is chosen.
  String get chosenLabel => short ?? label;
}

/// One line of the sheet's head: 산지, then 프랑스 > 보르도.
@immutable
class TasteCardNoteFactViewData {
  const TasteCardNoteFactViewData({required this.label, required this.value})
    : assert(label != ''),
      assert(value != '');

  final String label;
  final String value;
}

/// What the reader took one way, under the server's name for it: 마음에 들었어요,
/// then 체리 · 자두. The sheet draws the groups as given.
@immutable
class TasteCardNoteGroupViewData {
  const TasteCardNoteGroupViewData({required this.label, required this.marks})
    : assert(label != '');

  final String label;
  final List<TasteCardNoteMarkViewData> marks;
}

/// How the reader took one thing on the sheet: liked, or too much ([less]),
/// too little ([more]) or out of place ([burden]), which the sheet draws
/// alike.
enum TasteCardNoteFelt {
  liked,
  less,
  more,
  burden,

  /// Noticed, with no opinion given: drawn plain.
  noticed,
}

/// One thing the reader marked: 체리 liked, 떫음 less.
@immutable
class TasteCardNoteMarkViewData {
  const TasteCardNoteMarkViewData({
    required this.label,
    this.felt = TasteCardNoteFelt.noticed,
  }) : assert(label != '');

  final String label;
  final TasteCardNoteFelt felt;
}

/// One row of 맛 밸런스 or 여운 밸런스: the bottle's own level and what the
/// reader said of it.
@immutable
class TasteCardNoteBalanceViewData {
  const TasteCardNoteBalanceViewData({
    required this.label,
    this.key,
    this.mark,
    this.word,
    this.felt,
    this.said,
    this.level,
    this.ends,
  }) : assert(mark == null || (mark >= 1 && mark <= 5)),
       assert(level == null || (level >= 1 && level <= 5));

  /// The axis the row is of (sweetness, body); null on a card stored before
  /// rows carried one.
  final String? key;
  final String label;

  /// The bottle's level, 1 to 5; null draws no gauge.
  final int? mark;

  /// The level as a word: 드라이, 탄탄한 타닌.
  final String? word;

  /// Null when the reader said nothing of this taste.
  final TasteCardNoteFelt? felt;

  /// The reader's remark in their answer's words: 은은해서 좋았어요, or the
  /// term of the step they chose on the gauge (드라이).
  final String? said;

  /// The step the reader chose on the gauge, 1 to 5; null on a row not
  /// answered, and on a card answered before the gauges.
  final int? level;

  /// What the gauge's two ends lean to, on an axis that runs between two
  /// characters and not from little to much (끝맛의 인상); null otherwise.
  final (String low, String high)? ends;
}
