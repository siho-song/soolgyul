import '../../home/data/next_drink_guides.dart';
import '../../home/data/taste_letters.dart';
import '../../taste_card/data/taste_card_snapshot_view_data.dart';

/// The bottle's photo in the catalog's storage, under the server's address.
const homeTourExamplePhotoPath =
    '/storage/v1/object/public/alcohol-product-images/whisky/'
    '24d5b897-b1c6-5235-8b3b-b4e6b8bca0d3.webp';

/// What the tour shows a member who has no card yet: a card the engine
/// wrote for one first record of 조니워커 블랙 라벨, and the home that
/// record would fill.
TasteCardSnapshotViewData homeTourExampleCard({
  String? photoUrl,
}) => TasteCardSnapshotViewData(
  product: TasteCardProductViewData(
    imageReference: photoUrl == null
        ? null
        : TasteCardImageReference(
            source: TasteCardImageSource.catalog,
            reference: photoUrl,
          ),
    drinkNameSnapshot: '조니워커 블랙 라벨',
    categoryLabel: '위스키',
    styleLabel: '블렌디드 위스키',
    abvPercent: 40,
  ),
  bite: const TasteCardBiteViewData(
    nickname: '선명한 스위트 러버',
    tags: <TasteCardTagViewData>[
      TasteCardTagViewData(label: '캐러멜·바닐라향', kind: TasteCardTagKind.liked),
      TasteCardTagViewData(
        label: '단맛',
        kind: TasteCardTagKind.liked,
        term: TasteCardTermViewData(
          word: '단맛',
          label: '체감 단맛',
          kind: '맛',
          description: '설탕물이나 꿀을 머금었을 때처럼 혀끝에서 직관적으로 감지되는 달콤함의 세기예요',
        ),
      ),
      TasteCardTagViewData(
        label: '스모키향',
        kind: TasteCardTagKind.burden,
        term: TasteCardTermViewData(
          word: '스모키향',
          label: '스모키',
          kind: '향',
          description: '참나무 장작불이나 숯불 바비큐 곁에서 맡는 그윽하고 아늑한 탄내예요',
        ),
      ),
    ],
    summary:
        '향긋한 **캐러멜·바닐라 향**, 달콤한 **풍미**, 은은하게 맴도는 **여운**은 반갑지만, 너무 진하게 올라오는 **스모키 향**과 확 올라오는 알코올 **열감**은 아직 조금 버거워요.',
    brief: '캐러멜·바닐라 향, 달콤함, 여운은 반갑지만, 스모키 향과 열감은 아직 조금 버거워요.',
    guide: _exampleGuide,
  ),
  positive: const <TasteCardParagraphViewData>[
    TasteCardParagraphViewData(
      answer: '서로 다른 향의 조화와 포근하게 남는 단맛',
      text:
          '이 위스키에서는 **캐러멜**의 구수함과 **바닐라**의 달큰함이 함께 어우러지는데, 결이 다른 향들이 한 잔에 담기면 한 가지 향일 때보다 훨씬 입체적이고 다채롭게 다가와요. 또한 신맛이 거의 없어서, 원래 **단맛**을 깎아 산뜻하게 만들던 신맛이 빠진 만큼 단맛이 그대로 둥글고 포근하게 남아요. 이 두 가지 특징이 입안에서 **기분 좋은 매력**으로 다가온 것 같아요.',
      terms: <TasteCardTermViewData>[
        TasteCardTermViewData(
          word: '캐러멜',
          label: '캐러멜',
          kind: '향',
          description: '설탕을 냄비에 진하게 졸여 만든 사탕처럼 달콤하고 고소한 향이에요',
        ),
        TasteCardTermViewData(
          word: '바닐라',
          label: '바닐라',
          kind: '향',
          description: '바닐라 아이스크림처럼 부드럽고 포근하게 퍼지는 달콤한 향이에요',
        ),
        TasteCardTermViewData(
          word: '단맛',
          label: '체감 단맛',
          kind: '맛',
          description: '설탕물이나 꿀을 머금었을 때처럼 혀끝에서 직관적으로 감지되는 달콤함의 세기예요',
        ),
      ],
    ),
  ],
  burden: const <TasteCardParagraphViewData>[
    TasteCardParagraphViewData(
      answer: '벽처럼 다 덮는 스모키 향과 단맛보다 먼저 오는 열감',
      text:
          '**스모키 향**은 적은 양에도 코가 먼저 알아채는 연기 냄새라서, 세게 앞서면 뒤에 올 향과 맛의 자리까지 벽처럼 다 덮어 버려요. 게다가 **단맛**과 알코올의 온기를 함께 지니고 있어서, 온기가 단맛이 밋밋하지 않게 받쳐 주지만 그 몫을 넘어서면 좋아하신 단맛보다 **열감**이 먼저 다가와요. 이 두 가지 특징이 **부담**으로 다가온 것 같아요.',
      terms: <TasteCardTermViewData>[
        TasteCardTermViewData(
          word: '스모키 향',
          label: '스모키',
          kind: '향',
          description: '참나무 장작불이나 숯불 바비큐 곁에서 맡는 그윽하고 아늑한 탄내예요',
        ),
        TasteCardTermViewData(
          word: '단맛',
          label: '체감 단맛',
          kind: '맛',
          description: '설탕물이나 꿀을 머금었을 때처럼 혀끝에서 직관적으로 감지되는 달콤함의 세기예요',
        ),
      ],
    ),
  ],
  snapshotRef: 'example:home-tour',
);

const _exampleGuide = TasteCardGuideViewData(
  head: '좋았던 매력은 살리고 부담은 줄인 블렌디드 위스키의 추천 키워드예요.',
  picks: <TasteCardGuidePickViewData>[
    TasteCardGuidePickViewData(
      keyword: '차링 캐스크(Charred)',
      note:
          '내부를 직화로 강하게 태워 만든 숯 층이 미성숙한 잡맛을 걸러내고 농밀한 단맛과 진한 호박색을 입혀줘요. 달콤하고 고소한 캐러멜 향이 나요.',
      term: TasteCardTermViewData(
        word: '차링 캐스크(Charred)',
        label: '차링 캐스크',
        kind: '제조·숙성',
        description:
            '오크통 내부를 직화로 강하게 태워 탄화 숯 층을 만드는 공정이에요. 활성탄 층이 거친 잡미를 흡착하고 열 분해된 목재 층에서 바닐라와 캐러멜 향, 진한 호박색을 더해줘요.',
      ),
    ),
    TasteCardGuidePickViewData(
      keyword: '스몰 배치(Small Batch)',
      note:
          '대량 생산 대신 엄선한 소수의 뛰어난 캐스크만 한정 선별하여 뚜렷한 농축감과 세밀한 완성도를 보여줘요. 달콤한 바닐라 향이 나요.',
      term: TasteCardTermViewData(
        word: '스몰 배치(Small Batch)',
        label: '스몰 배치',
        kind: '제조·숙성',
        description:
            "고른 통 몇 개만 섞어 만든 술이라는 표시예요. 다만 몇 통까지가 '소량'인지 정한 규정이 없어서, 생산자마다 뜻이 달라요.",
      ),
    ),
  ],
  tip: '바(Bar) 메뉴판이나 바틀 라벨에서 위 단어를 찾아보세요!',
  levels: <TasteCardGuideLevelViewData>[
    TasteCardGuideLevelViewData(label: '도수', mark: 2, range: '40~43%'),
  ],
  directions: <TasteCardGuideDirectionViewData>[
    TasteCardGuideDirectionViewData(
      word: '단맛',
      change: TasteCardGuideChange.keep,
    ),
    TasteCardGuideDirectionViewData(
      word: '캐러멜 향',
      change: TasteCardGuideChange.keep,
    ),
    TasteCardGuideDirectionViewData(
      word: '바닐라 향',
      change: TasteCardGuideChange.keep,
    ),
    TasteCardGuideDirectionViewData(
      word: '스모키 향',
      change: TasteCardGuideChange.lower,
    ),
    TasteCardGuideDirectionViewData(
      word: '알코올 열감',
      change: TasteCardGuideChange.lower,
    ),
  ],
);

/// The letters that record opens: 풍 · 달 · ? · 길. It said nothing of the
/// weight, so that place stays empty.
const homeTourExampleLetters = TasteLettersState(
  axes: <TasteLetterAxis, TasteLetterAxisState>{
    TasteLetterAxis.aroma: TasteLetterAxisState(
      letter: 'R',
      rightShare: 100,
      voteCount: 1,
    ),
    TasteLetterAxis.sweetness: TasteLetterAxisState(
      letter: 'S',
      rightShare: 100,
      voteCount: 1,
    ),
    TasteLetterAxis.finish: TasteLetterAxisState(
      letter: 'P',
      rightShare: 100,
      voteCount: 1,
    ),
  },
  recordCount: 1,
);

const homeTourExampleGuides = <NextDrinkGuide>[
  NextDrinkGuide(
    resultId: 'example:home-tour',
    kindLabel: '블렌디드 위스키',
    categoryLabel: '위스키',
    guide: _exampleGuide,
  ),
];
