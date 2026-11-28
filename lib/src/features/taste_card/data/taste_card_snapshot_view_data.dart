import 'package:flutter/foundation.dart';

import 'taste_card_note_view_data.dart';

export 'taste_card_note_view_data.dart';

/// The rendered card the taste-card screen shows: the product, then the three
/// parts the server wrote. 술결 한입 (별명 · 핵심 요약 · 다음 술 가이드),
/// 왜 잘 맞았을까요, 왜 부담이었을까요, and on the balanced card (every taste
/// 적당했어요) 왜 편안했을까요 instead.
///
/// This is the information shape the viewer renders; the JSON wire is parsed
/// by `TasteCardWireParser` and never read by widgets.
@immutable
class TasteCardSnapshotViewData {
  const TasteCardSnapshotViewData({
    required this.product,
    required this.bite,
    required this.positive,
    required this.burden,
    this.balanced = const <TasteCardParagraphViewData>[],
    required this.snapshotRef,
    this.recordedAt,
    this.note,
  }) : assert(snapshotRef != '');

  final TasteCardProductViewData product;
  final TasteCardBiteViewData bite;

  /// 왜 잘 맞았을까요: empty when nothing matched, and then not shown.
  final List<TasteCardParagraphViewData> positive;

  /// 왜 부담이었을까요: empty when nothing weighed, and then not shown.
  final List<TasteCardParagraphViewData> burden;

  /// 왜 편안했을까요: only the balanced card has these.
  final List<TasteCardParagraphViewData> balanced;
  final String snapshotRef;

  /// When the card was written, which is when the drink was recorded.
  final DateTime? recordedAt;

  /// 테이스팅 노트, the card's second tab; null on a card stored before it
  /// was written, and then the card has no tabs.
  final TasteCardNoteViewData? note;

  TasteCardProductViewData get header => product;
}

@immutable
class TasteCardProductViewData {
  const TasteCardProductViewData({
    required this.drinkNameSnapshot,
    this.userName,
    this.imageReference,
    this.categoryLabel,
    this.styleLabel,
    this.abvPercent,
  }) : assert(drinkNameSnapshot != '');

  final String drinkNameSnapshot;
  final String? userName;
  final TasteCardImageReference? imageReference;
  final String? categoryLabel;

  /// 준마이 긴조, 레드 와인; older cards carry neither this nor the ABV.
  final String? styleLabel;
  final double? abvPercent;
}

/// 술결 한입: the nickname, the 핵심 요약 (tags, then one line) and the guide.
@immutable
class TasteCardBiteViewData {
  const TasteCardBiteViewData({
    required this.nickname,
    required this.tags,
    required this.summary,
    this.brief,
    this.guide,
    this.next,
  }) : assert(nickname != ''),
       assert(summary != '');

  final String nickname;

  /// One chip per sensation the reader answered: its name and which way.
  final List<TasteCardTagViewData> tags;

  /// The one line under the tags.
  final String summary;

  /// [summary] with its dressing left off, for a record card's one line;
  /// null on cards made before it was written.
  final String? brief;

  /// The guide of a card written before 2026-11-21. It is read as the card
  /// stores it; no screen draws it.
  final TasteCardGuideViewData? guide;

  /// 다음 방향; null on a card stored before it or with
  /// nothing to say.
  final TasteCardNextViewData? next;
}

/// One line of 다음 방향: what to choose next and what choosing so does, the
/// names to look for in bold.
@immutable
class TasteCardNextLineViewData {
  const TasteCardNextLineViewData({
    required this.text,
    this.terms = const <TasteCardTermViewData>[],
  });

  /// The sentence, the names to look for between ** marks.
  final String text;

  /// The explanations of the marked names.
  final List<TasteCardTermViewData> terms;
}

/// 다음 방향: what to choose next, a sentence a line.
@immutable
class TasteCardNextViewData {
  const TasteCardNextViewData({required this.lines});

  final List<TasteCardNextLineViewData> lines;

  bool get isEmpty => lines.isEmpty;
}

/// 다음 술은 이렇게 골라보세요, as a card stores it: the head sentence, the
/// picks, a profile in words, the levels and a tip. No screen draws it.
@immutable
class TasteCardGuideViewData {
  const TasteCardGuideViewData({
    required this.head,
    this.picks = const <TasteCardGuidePickViewData>[],
    this.tip,
    this.levels = const <TasteCardGuideLevelViewData>[],
    this.profile = const <TasteCardGuideProfileLineViewData>[],
  }) : assert(head != '');

  final String head;

  /// What to look for on a label or menu, one chip each.
  final List<TasteCardGuidePickViewData> picks;

  /// How to use the guide in a shop: the small caption at the bottom.
  final String? tip;

  /// The 1–5 marks to look for, one gauge each.
  final List<TasteCardGuideLevelViewData> levels;

  /// The drink to look for said in words (a whisky: AROMA, FLAVOR, FINISH);
  /// empty for a kind shown by gauges and on a card stored before it.
  final List<TasteCardGuideProfileLineViewData> profile;
}

/// One pick: flag and place, then the label words, with why under them.
@immutable
class TasteCardGuidePickViewData {
  const TasteCardGuidePickViewData({
    required this.keyword,
    this.words = const <TasteCardGuideWordViewData>[],
    this.labelWord,
    this.country,
    this.place,
    this.note,
    this.term,
  }) : assert(keyword != '');

  /// ISO 3166-1 alpha-2 of the country whose flag leads the chip.
  final String? country;
  final String? place;

  /// The chip's words in one line; what a card stored before [words] shows.
  final String keyword;

  /// The chip's label words one by one, Merlot(메를로) or dry and trocken;
  /// empty on a card stored before chips carried them.
  final List<TasteCardGuideWordViewData> words;

  /// Whether the chip is words printed on the label (dry, 山廃) and not a
  /// grape, a region or a grade; null on a card stored before chips said so.
  final bool? labelWord;

  /// Why this is picked for this reader, under the chip.
  final String? note;

  /// The explanation of [keyword] on a card without [words]; the reader
  /// opens it by touching the chip's name.
  final TasteCardTermViewData? term;

  /// The words the chip shows: its own, or [keyword] as the one word.
  List<TasteCardGuideWordViewData> get shownWords => words.isNotEmpty
      ? words
      : <TasteCardGuideWordViewData>[
          TasteCardGuideWordViewData(text: keyword, term: term),
        ];

  /// What [keyword] says after its words, written as it is: ' 없는 것' of
  /// 'Peated(피트 처리 맥아) 없는 것'. Null when the words are the whole line.
  String? get trail {
    if (words.isEmpty) return null;
    final line = words.map((word) => word.text).join(' · ');
    return keyword.startsWith(line) && keyword.length > line.length
        ? keyword.substring(line.length)
        : null;
  }
}

/// One label word of a chip as it is printed and read, Merlot(메를로), and
/// the dictionary's explanation of it when it has one.
@immutable
class TasteCardGuideWordViewData {
  const TasteCardGuideWordViewData({required this.text, this.term})
    : assert(text != '');

  final String text;
  final TasteCardTermViewData? term;
}

/// One gauge: the mark to look for, 1 to 5, and the range in the label's words.
@immutable
class TasteCardGuideLevelViewData {
  const TasteCardGuideLevelViewData({
    required this.label,
    required this.mark,
    required this.range,
    this.word,
    this.term,
  }) : assert(mark >= 1 && mark <= 5);

  final String label;
  final int mark;
  final String range;

  /// The mark as a word a shop would use: 드라이, 미디엄 바디; null on a
  /// card stored before marks carried one.
  final String? word;

  /// The explanation of the gauge's name (당도, 타닌); null when it has none.
  final TasteCardTermViewData? term;
}

/// One line of a drink said in words: AROMA, then 바닐라 · 꿀.
@immutable
class TasteCardGuideProfileLineViewData {
  const TasteCardGuideProfileLineViewData({
    required this.label,
    required this.words,
  }) : assert(label != '');

  final String label;
  final List<String> words;
}

/// Which way a 핵심 요약 tag points; the card draws each kind as its icon.
enum TasteCardTagKind {
  /// 좋았어요: a heart.
  liked,

  /// 부담, 너무 셌거나 끝에 오래 남았어요: an arrow down.
  less,

  /// 부담, 어울리지 않았어요: a prohibit sign.
  burden,

  /// 너무 약했어요 / 너무 짧았어요: an arrow up.
  more,

  /// 적당했어요 (the balanced card): a check.
  fine;

  /// The kind the server sends by this key (each is sent by its name), or
  /// null for a key this app does not know.
  static TasteCardTagKind? fromKey(Object? key) => values.asNameMap()[key];
}

/// One 핵심 요약 tag: 흙향 liked, 떫은맛 less, 단맛 more.
@immutable
class TasteCardTagViewData {
  const TasteCardTagViewData({
    required this.label,
    required this.kind,
    this.term,
  }) : assert(label != '');

  final String label;
  final TasteCardTagKind kind;

  /// The dictionary's explanation of the tag's sensation; null when it has none.
  final TasteCardTermViewData? term;
}

/// One paragraph of a reason section: the reader's answer, then the sentences.
@immutable
class TasteCardParagraphViewData {
  const TasteCardParagraphViewData({
    required this.answer,
    required this.text,
    this.terms = const <TasteCardTermViewData>[],
  }) : assert(answer != ''),
       assert(text != '');

  final String answer;
  final String text;

  /// The **marked** words of the text that the dictionary explains; the
  /// reader opens one by touching it. Other marked words are the verdict.
  final List<TasteCardTermViewData> terms;
}

/// A word the card uses, the dictionary's name for it and its explanation.
@immutable
class TasteCardTermViewData {
  const TasteCardTermViewData({
    required this.word,
    required this.label,
    required this.kind,
    required this.description,
    this.key,
  }) : assert(word != ''),
       assert(label != ''),
       assert(description != '');

  /// As the card writes it: 체리 향, 산미, or a tag's 체리향.
  final String word;

  /// The dictionary's name: 체리, 산미, 떫음.
  final String label;

  /// 향, 맛, 질감, 여운.
  final String kind;
  final String description;

  /// The dictionary's key of the term (aroma:cherry), by which 나의 용어 사전
  /// saves it; `null` on a card served before terms carried one.
  final String? key;
}

enum TasteCardImageSource { userPhoto, catalog, categoryFallback }

@immutable
class TasteCardImageReference {
  const TasteCardImageReference({required this.source, required this.reference})
    : assert(reference != '');

  final TasteCardImageSource source;
  final String reference;
}
