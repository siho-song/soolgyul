import 'package:flutter/foundation.dart';

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

  TasteCardProductViewData get header => product;
}

@immutable
class TasteCardProductViewData {
  const TasteCardProductViewData({
    required this.drinkNameSnapshot,
    this.userName,
    this.imageReference,
    this.categoryLabel,
  }) : assert(drinkNameSnapshot != '');

  final String drinkNameSnapshot;
  final String? userName;
  final TasteCardImageReference? imageReference;
  final String? categoryLabel;
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

  /// 다음 술은 이렇게 골라보세요; null when nothing in the dictionary fits.
  final TasteCardGuideViewData? guide;
}

/// 다음 술은 이렇게 골라보세요: the head sentence, then the parts the card
/// draws as chips, gauges and directions, with a caption under them.
@immutable
class TasteCardGuideViewData {
  const TasteCardGuideViewData({
    required this.head,
    this.picks = const <TasteCardGuidePickViewData>[],
    this.tip,
    this.levels = const <TasteCardGuideLevelViewData>[],
    this.directions = const <TasteCardGuideDirectionViewData>[],
  }) : assert(head != '');

  final String head;

  /// What to look for on a label or menu, one chip each.
  final List<TasteCardGuidePickViewData> picks;

  /// 와인 라벨에서 이 특징을 찾아보세요: the small caption at the bottom.
  final String? tip;

  /// The 1–5 marks to look for, one gauge each.
  final List<TasteCardGuideLevelViewData> levels;

  /// 이번 술을 기준으로: keep a liked thing, turn a burden down or up.
  final List<TasteCardGuideDirectionViewData> directions;
}

/// One pick: flag and place, then the keyword, with what it brings under it.
@immutable
class TasteCardGuidePickViewData {
  const TasteCardGuidePickViewData({
    required this.keyword,
    this.country,
    this.place,
    this.note,
  }) : assert(keyword != '');

  /// ISO 3166-1 alpha-2 of the country whose flag leads the chip.
  final String? country;
  final String? place;
  final String keyword;
  final String? note;
}

/// One gauge: the mark to look for, 1 to 5, and the range in the label's words.
@immutable
class TasteCardGuideLevelViewData {
  const TasteCardGuideLevelViewData({
    required this.label,
    required this.mark,
    required this.range,
  }) : assert(mark >= 1 && mark <= 5);

  final String label;
  final int mark;
  final String range;
}

enum TasteCardGuideChange { keep, lower, higher }

@immutable
class TasteCardGuideDirectionViewData {
  const TasteCardGuideDirectionViewData({
    required this.word,
    required this.change,
  });

  final String word;
  final TasteCardGuideChange change;
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
  fine,
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
}

enum TasteCardImageSource { userPhoto, catalog, categoryFallback }

@immutable
class TasteCardImageReference {
  const TasteCardImageReference({required this.source, required this.reference})
    : assert(reference != '');

  final TasteCardImageSource source;
  final String reference;
}
