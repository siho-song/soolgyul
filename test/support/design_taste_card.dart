import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';

/// The engine's own card for the 샤또 마고 fixture, for tests that need a
/// card the server wrote.
const designTasteCard = TasteCardSnapshotViewData(
  product: TasteCardProductViewData(
    drinkNameSnapshot: '샤또 마고',
    userName: '수연',
    categoryLabel: '와인',
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
