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

  /// Visual reference content for design QA and local preview only: the
  /// engine's own card for the 샤또 마고 fixture (BP-01).
  static const designFixture = TasteCardSnapshotViewData(
    product: TasteCardProductViewData(
      drinkNameSnapshot: '샤또 마고',
      userName: '수연',
      categoryLabel: '와인',
      imageReference: TasteCardImageReference(
        source: TasteCardImageSource.categoryFallback,
        reference:
            'assets/component_assets/taste_card/design_fixture_bottle.png',
      ),
    ),
    bite: TasteCardBiteViewData(
      nickname: '선명한 프루티 러버',
      tags: <TasteCardTagViewData>[
        TasteCardTagViewData(label: '체리향', kind: TasteCardTagKind.liked),
        TasteCardTagViewData(label: '산미', kind: TasteCardTagKind.liked),
        TasteCardTagViewData(label: '떫은맛', kind: TasteCardTagKind.less),
      ],
      summary:
          '싱그러운 **체리 향**과 침샘을 자극하는 깔끔한 **산미**는 반갑지만, '
          '입안을 꽉 조이는 **떫은맛**은 아직 조금 버거워요.',
      guide: TasteCardGuideViewData(
        head: '좋았던 매력은 살리고 부담은 줄인 레드 와인을 품종과 산지 조합으로 준비했어요.',
        picks: <TasteCardGuidePickViewData>[
          TasteCardGuidePickViewData(
            country: 'it',
            place: '이탈리아 피에몬테',
            keyword: '바르베라',
          ),
          TasteCardGuidePickViewData(
            country: 'it',
            place: '이탈리아 베네토',
            keyword: '코르비나',
          ),
        ],
        tip: '와인 라벨(앞·뒷면)이나 매장 설명 카드에서 이 특징을 찾아보세요!',
        levels: <TasteCardGuideLevelViewData>[
          TasteCardGuideLevelViewData(label: '당도', mark: 1, range: '1~2'),
          TasteCardGuideLevelViewData(label: '산도', mark: 4, range: '4'),
          TasteCardGuideLevelViewData(label: '타닌', mark: 2, range: '2'),
          TasteCardGuideLevelViewData(label: '바디', mark: 4, range: '3~4'),
        ],
      ),
    ),
    positive: <TasteCardParagraphViewData>[
      TasteCardParagraphViewData(
        answer: '또렷한 과일 향과 깔끔하게 떨어지는 산미',
        text:
            '이 와인은 향이 짙고 또렷한 특징을 가지고 있어서, 여러 풍미가 섞여 '
            '있어도 **체리 향**이 묻히지 않고 선명하게 피어올라요. 또한 단맛이 '
            '거의 없어서, 원래 신맛을 감싸 주던 단맛이 빠진 만큼 **산미** 특유의 '
            '산뜻함이 그대로 드러나요. 이 두 가지 특징이 입안에서 **기분 좋은 '
            '매력**으로 다가온 것 같아요.',
      ),
    ],
    burden: <TasteCardParagraphViewData>[
      TasteCardParagraphViewData(
        answer: '떫은 조임과 길게 이어지는 텁텁함',
        text:
            '이 와인은 질감은 매끄럽지만 타닌이 많아서, **떫은 조임**이 혀와 '
            '입안을 붙들며 본래의 매끄러운 촉감을 가려 버려요. 게다가 떫은 맛이 '
            '센 만큼, 침과 엉겨 붙은 조임이 침이 다시 돌 때까지 삼킨 뒤에도 입안에 '
            '남아요. 이 두 가지 특징이 **부담**으로 다가온 것 같아요.',
      ),
    ],
    snapshotRef: 'fixture:design:v3',
  );
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
