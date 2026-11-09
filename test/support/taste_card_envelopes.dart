import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';

/// The guide as the server sends it: picks, a tip, and the marks to look for.
const Map<String, Object?> defaultGuideJson = <String, Object?>{
  'head': '떫은맛만 줄인 레드 와인으로 가보세요.',
  'picks': <Object?>[
    <String, Object?>{
      'country': 'it',
      'place': '이탈리아 피에몬테',
      'keyword': '바르베라',
      'note': null,
    },
    <String, Object?>{
      'country': 'fr',
      'place': '프랑스 보졸레',
      'keyword': '가메',
      'note': null,
    },
  ],
  'tip': '와인 라벨(앞·뒷면)이나 매장 설명 카드에서 이 특징을 찾아보세요!',
  'levels': <Object?>[
    <String, Object?>{'label': '당도', 'mark': 1, 'range': '1~2'},
    <String, Object?>{'label': '타닌', 'mark': 2, 'range': '2'},
  ],
  'directions': <Object?>[],
};

/// A saved result envelope as the server sends it: the three-part card.
Map<String, Object?> validEnvelope({
  bool withBurden = true,
  bool withPositive = true,
  bool withBalanced = false,
  Object? guide = defaultGuideJson,
}) => <String, Object?>{
  'wire_schema_version': tasteCardWireSchemaVersion,
  'result_id': '20000000-0000-4000-8000-000000000002',
  'record_id': '30000000-0000-4000-8000-000000000002',
  'snapshot_ref': 'snapshot-v3',
  'ownership_state': 'saved',
  'alcohol_identification': <String, Object?>{
    'mode': 'catalog_match',
    'alcohol_item_id': 'alcohol-v3',
    'alcohol_name_snapshot': '테스트 리슬링',
    'category': 'wine',
  },
  'view': <String, Object?>{
    'product': <String, Object?>{
      'drink_name_snapshot': '테스트 리슬링',
      'user_name': '민지',
      'image_reference': null,
      'category_label': '와인',
    },
    'bite': <String, Object?>{
      'nickname': '선명한 프루티 러버',
      'tags': <Object?>[
        <String, Object?>{'label': '복숭아향', 'kind': 'liked'},
        <String, Object?>{'label': '산미', 'kind': 'liked'},
        <String, Object?>{'label': '떫은맛', 'kind': 'less'},
      ],
      'summary':
          '싱그러운 **복숭아 향**과 침샘을 자극하는 깔끔한 **산미**는 반갑지만, '
          '입안을 꽉 조이는 **떫은맛**은 아직 조금 버거워요.',
      'brief': '복숭아 향과 산미는 반갑지만, 떫은맛은 아직 조금 버거워요.',
      'guide': guide,
    },
    'positive': <Object?>[
      if (withPositive)
        paragraphJson(
          answer: '또렷한 과일 향과 깔끔하게 떨어지는 산미',
          text:
              '이 와인은 향이 짙어서 여러 풍미가 섞여 있어도 **복숭아 향**이 또렷하게 피어올라요. '
              '또한 단맛이 거의 없어서 **산미** 특유의 산뜻함이 그대로 드러나요. '
              '이 두 가지 특징이 입안에서 **기분 좋은 매력**으로 다가온 것 같아요.',
        ),
    ],
    'burden': <Object?>[
      if (withBurden)
        paragraphJson(
          answer: '떫은 조임',
          text:
              '이 와인은 타닌이 많아서 **떫은 조임**이 혀와 입안을 붙들며 본래의 매끄러운 촉감을 가려 버려요. '
              '이 특징이 **부담**으로 다가온 것 같아요.',
        ),
    ],
    'balanced': <Object?>[
      if (withBalanced)
        paragraphJson(
          answer: '산미가 튀지 않고 적당했어요',
          text: '사실 테스트 리슬링은 일반 와인보다 산미가 꽤 높은 편(산도 4)에 속해요.',
        ),
    ],
    'metadata': <String, Object?>{
      'snapshot_ref': 'snapshot-v3',
      'schema_version': 3,
      'engine_version': 'card-facts-v2',
      'generated_at': '2026-10-29T00:00:00.000Z',
      'generated_from_record_ref': '30000000-0000-4000-8000-000000000002',
    },
  },
  'conversion': null,
  'created_at': '2026-10-29T00:00:00.000Z',
};

Map<String, Object?> paragraphJson({
  required String answer,
  required String text,
  List<Map<String, Object?>>? terms,
}) => <String, Object?>{'answer': answer, 'text': text, 'terms': ?terms};

/// A served card's explanation of one word, as the server attaches it.
Map<String, Object?> termJson(
  String word, {
  String label = '산미',
  String kind = '맛',
  String description = '레몬이나 풋사과를 깨물었을 때처럼 입안 가득 침이 고이게 만드는 새콤하고 청량한 맛의 강도예요',
}) => <String, Object?>{
  'word': word,
  'label': label,
  'kind': kind,
  'description': description,
};

Map<String, Object?> viewOf(Map<String, Object?> envelope) =>
    envelope['view']! as Map<String, Object?>;

Map<String, Object?> objectAt(Map<String, Object?> parent, String key) =>
    parent[key]! as Map<String, Object?>;
