// Temporary: refactor guard. Deleted with refactor_guard/ when the refactor ends.
//
// Walks the main flows on fixed fake data at two phone sizes and draws the
// data-rich and interactive states along the way, so a refactor can prove
// it changed no pixel. Camera and label reading are left out: they need
// device plugins.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/features/auth/social_auth_service.dart';
import 'package:soolgyul/src/features/catalog/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';
import 'package:soolgyul/src/features/home/data/next_drink_guides.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/features/recording/presentation/drink_search_screen.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_parser.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_fit/data/taste_fit_gateway.dart';
import 'package:soolgyul/src/features/taste_fit/taste_fit_verdict.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import '../test/support/app_test_harness.dart';
import '../test/support/taste_card_envelopes.dart';
import 'snap.dart';

// ---------------------------------------------------------------------------
// Fixed data
// ---------------------------------------------------------------------------

/// Catalog rows the fake search serves. One row carries a photo URL; the
/// test HTTP client answers every request with 400, so it always falls back
/// to the placeholder the same way.
const _catalog = <CatalogDrink>[
  CatalogDrink(
    id: 'p-johnnie-black',
    displayName: '조니워커 블랙 라벨',
    nameEn: 'Johnnie Walker Black Label',
    category: DrinkCategory.whisky,
    styleLabel: '블렌디드 위스키',
    abvPercent: 40,
  ),
  CatalogDrink(
    id: 'p-hwayo-25',
    displayName: '화요 25',
    nameEn: 'Hwayo 25',
    category: DrinkCategory.koreanTraditional,
    styleLabel: '증류식 소주',
    abvPercent: 25,
  ),
  CatalogDrink(
    id: 'p-montes-alpha-cs',
    displayName: '몬테스 알파 까베르네 소비뇽',
    nameEn: 'Montes Alpha Cabernet Sauvignon',
    category: DrinkCategory.redWine,
    styleLabel: '레드 와인',
    abvPercent: 14.5,
    photoUrl: 'https://guard.invalid/montes-alpha-cs.png',
  ),
  CatalogDrink(
    id: 'p-dassai-45',
    displayName: '닷사이 준마이 다이긴죠 45',
    nameEn: 'Dassai Junmai Daiginjo 45',
    category: DrinkCategory.sake,
    styleLabel: '준마이 다이긴죠',
    abvPercent: 16,
  ),
  CatalogDrink(
    id: 'p-boksoon-takju',
    displayName: '복순도가 탁주',
    category: DrinkCategory.koreanTraditional,
    styleLabel: '탁주',
    abvPercent: 6.5,
  ),
  CatalogDrink(
    id: 'p-montes-alpha-syrah',
    displayName: '몬테스 알파 시라',
    nameEn: 'Montes Alpha Syrah',
    category: DrinkCategory.redWine,
    styleLabel: '레드 와인',
    abvPercent: 14,
  ),
  CatalogDrink(
    id: 'p-cloudy-bay-sb',
    displayName: '클라우디 베이 소비뇽 블랑',
    nameEn: 'Cloudy Bay Sauvignon Blanc',
    category: DrinkCategory.whiteWine,
    styleLabel: '화이트 와인',
    abvPercent: 13.5,
  ),
  CatalogDrink(
    id: 'p-croisade-sb',
    displayName: '라 크라사드 소비뇽 블랑',
    nameEn: 'La Croisade Sauvignon Blanc',
    category: DrinkCategory.whiteWine,
    styleLabel: '화이트 와인',
    abvPercent: 12,
  ),
  CatalogDrink(
    id: 'p-sauvignon-unknown',
    displayName: '소비뇽 블랑 하우스 와인',
    category: DrinkCategory.whiteWine,
    styleLabel: '화이트 와인',
  ),
];

class _Catalog implements CatalogSearchGateway {
  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = catalogSearchPageSize,
    int offset = 0,
  }) async {
    final needle = query.replaceAll(' ', '').toLowerCase();
    return _catalog
        .where(
          (drink) => drink.displayName
              .replaceAll(' ', '')
              .toLowerCase()
              .contains(needle),
        )
        .skip(offset)
        .take(limit)
        .toList(growable: false);
  }
}

/// The served card: the shared envelope, with explained words on a tag and
/// in a reason, a guide with direction chips, and all three reasons.
TasteCardResult _servedCard() {
  final envelope = validEnvelope(
    withBalanced: true,
    guide: <String, Object?>{
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
        <String, Object?>{
          'country': 'es',
          'place': '스페인 리오하',
          'keyword': '템프라니요',
          'note': '오크 숙성이 짧은 크리안사급이면 더 편해요',
        },
      ],
      'tip': '와인 라벨(앞·뒷면)이나 매장 설명 카드에서 이 특징을 찾아보세요!',
      'levels': <Object?>[
        <String, Object?>{'label': '당도', 'mark': 1, 'range': '1~2'},
        <String, Object?>{'label': '산도', 'mark': 4, 'range': '3~4'},
        <String, Object?>{'label': '타닌', 'mark': 2, 'range': '2'},
      ],
      'directions': <Object?>[
        <String, Object?>{'word': '떫은맛', 'change': 'lower'},
        <String, Object?>{'word': '산미', 'change': 'keep'},
        <String, Object?>{'word': '과일 향', 'change': 'higher'},
      ],
    },
  );
  final view = viewOf(envelope);
  objectAt(view, 'bite')['tags'] = <Object?>[
    <String, Object?>{
      'label': '복숭아향',
      'kind': 'liked',
      'term': termJson(
        '복숭아향',
        label: '복숭아',
        kind: '향',
        description: '잘 익은 복숭아를 베어 물었을 때 퍼지는 달콤하고 보드라운 과즙 향이에요',
      ),
    },
    <String, Object?>{'label': '산미', 'kind': 'liked', 'term': termJson('산미')},
    <String, Object?>{'label': '떫은맛', 'kind': 'less'},
    <String, Object?>{'label': '묵직함', 'kind': 'fine'},
  ];
  view['positive'] = <Object?>[
    paragraphJson(
      answer: '또렷한 과일 향과 깔끔하게 떨어지는 산미',
      text:
          '이 와인은 향이 짙어서 여러 풍미가 섞여 있어도 **복숭아 향**이 또렷하게 피어올라요. '
          '또한 단맛이 거의 없어서 **산미** 특유의 산뜻함이 그대로 드러나요. '
          '이 두 가지 특징이 입안에서 **기분 좋은 매력**으로 다가온 것 같아요.',
      terms: <Map<String, Object?>>[termJson('산미')],
    ),
  ];
  return TasteCardWireParser.parseResult(envelope);
}

final _letters = TasteLettersSnapshot(
  state: TasteLettersState(
    axes: {
      TasteLetterAxis.aroma: const TasteLetterAxisState(
        letter: 'F',
        leftShare: 75,
        rightShare: 25,
        voteCount: 4,
      ),
      TasteLetterAxis.sweetness: const TasteLetterAxisState(
        letter: 'D',
        leftShare: 63,
        rightShare: 37,
        voteCount: 4,
      ),
      TasteLetterAxis.weight: TasteLetterAxisState.empty,
      TasteLetterAxis.finish: const TasteLetterAxisState(
        letter: 'C',
        leftShare: 50,
        rightShare: 50,
        voteCount: 2,
      ),
    },
    recordCount: 4,
  ),
  changes: <TasteLetterChange>[
    TasteLetterChange(
      axis: TasteLetterAxis.sweetness,
      toLetter: 'D',
      leftShare: 63,
      rightShare: 37,
      productName: '글렌피딕 12년',
      changedAt: DateTime(2026, 10, 2),
      resultId: 'result-glenfiddich',
    ),
    TasteLetterChange(
      axis: TasteLetterAxis.finish,
      toLetter: 'C',
      leftShare: 50,
      rightShare: 50,
      productName: '닷사이 준마이 다이긴죠 45',
      changedAt: DateTime(2026, 10, 11),
    ),
    TasteLetterChange(
      axis: TasteLetterAxis.aroma,
      fromLetter: 'R',
      toLetter: 'F',
      leftShare: 75,
      rightShare: 25,
      productName: '모스카토 다스티',
      changedAt: DateTime(2026, 10, 20),
      resultId: 'result-moscato',
    ),
  ],
);

class _Letters implements TasteLettersGateway {
  @override
  Future<TasteLettersSnapshot> load() async => _letters;
}

final _guides = <NextDrinkGuide>[
  NextDrinkGuide.fromRow(<String, Object?>{
    'result_id': 'result-red',
    'kind_label': '레드 와인',
    'category_label': '와인',
    'guide': defaultGuideJson,
  }, r'$guides[0]'),
  NextDrinkGuide.fromRow(<String, Object?>{
    'result_id': 'result-whisky',
    'kind_label': '싱글몰트 위스키',
    'category_label': '위스키',
    'guide': <String, Object?>{
      'head': '스모키함은 덜고 달콤한 오크를 살려보세요.',
      'picks': <Object?>[
        <String, Object?>{
          'country': null,
          'place': null,
          'keyword': '셰리 캐스크',
          'note': null,
        },
        <String, Object?>{
          'country': 'gb',
          'place': '스코틀랜드 스페이사이드',
          'keyword': '논피티드',
          'note': null,
        },
      ],
      'tip': null,
      'levels': <Object?>[
        <String, Object?>{'label': '당도', 'mark': 4, 'range': '3~4'},
        <String, Object?>{'label': '바디', 'mark': 3, 'range': '3'},
      ],
      'directions': <Object?>[
        <String, Object?>{'word': '스모키', 'change': 'lower'},
        <String, Object?>{'word': '단맛', 'change': 'higher'},
      ],
    },
  }, r'$guides[1]'),
  NextDrinkGuide.fromRow(<String, Object?>{
    'result_id': 'result-sake',
    'kind_label': '준마이 다이긴죠',
    'category_label': '사케',
    'guide': <String, Object?>{
      'head': '향이 화사한 다이긴죠를 차갑게 즐겨보세요.',
      'picks': <Object?>[
        <String, Object?>{
          'country': 'jp',
          'place': '일본 야마구치',
          'keyword': '준마이 다이긴죠',
          'note': '정미율 50% 이하',
        },
      ],
      'tip': '병 뒷면의 정미율과 일본주도를 확인해보세요.',
      'levels': <Object?>[
        <String, Object?>{'label': '당도', 'mark': 3, 'range': '2~3'},
      ],
      'directions': <Object?>[],
    },
  }, r'$guides[2]'),
];

class _Guides implements NextDrinkGuidesGateway {
  @override
  Future<List<NextDrinkGuide>> load() async => _guides;
}

const _verdicts = <String, TasteFitVerdict>{
  'p-cloudy-bay-sb': TasteFitVerdict(
    productId: 'p-cloudy-bay-sb',
    badge: TasteFitBadge.star,
    headline: '딱 맞는 PICK !',
    tags: <String>['#상큼한_과일향', '#침고이는_산미', '#가벼운_바디'],
    sentence:
        '평소 민지님께서 좋아하신 상큼한 과일 향, 산뜻한 산미, 가벼운 목넘김을 갖고 있는 술이라 시도해 보셔도 괜찮아요.',
    levels: <String, int>{
      'sweetness': 1,
      'acidity': 5,
      'astringency': 1,
      'body': 2,
    },
    facts: <TasteFitFact>[
      TasteFitFact(kind: 'producer', label: '클라우디 베이'),
      TasteFitFact(
        kind: 'grape',
        label: '소비뇽 블랑',
        description: '향이 또렷한 청포도 품종이에요.',
      ),
      TasteFitFact(
        kind: 'region',
        label: '말버러',
        description: '뉴질랜드 남섬 북단, 서늘하고 맑은 산지예요.',
      ),
    ],
  ),
  'p-montes-alpha-cs': TasteFitVerdict(
    productId: 'p-montes-alpha-cs',
    badge: TasteFitBadge.caution,
    headline: '아쉬운 PICK !',
    tags: <String>['#강한_떫은맛', '#묵직한_바디'],
    sentence: '떫은맛이 강하고 무게감이 있는 편이라 평소 취향보다 부담스러우실 수 있어요.',
    levels: <String, int>{
      'sweetness': 1,
      'acidity': 3,
      'astringency': 4,
      'body': 4,
      'finish_length': 4,
    },
    facts: <TasteFitFact>[
      TasteFitFact(kind: 'producer', label: '몬테스'),
      TasteFitFact(
        kind: 'grape',
        label: '까베르네 소비뇽',
        description: '껍질이 두꺼워 타닌이 단단한 적포도 품종이에요.',
      ),
      TasteFitFact(kind: 'region', label: '콜차과 밸리'),
    ],
  ),
  'p-croisade-sb': TasteFitVerdict(
    productId: 'p-croisade-sb',
    badge: TasteFitBadge.neutral,
    headline: '무난한 PICK !',
    tags: <String>['#은은한_과일향'],
    sentence: '취향과 크게 어긋나는 점은 없어요.',
    levels: <String, int>{'sweetness': 2, 'acidity': 4, 'body': 2},
  ),
  'p-johnnie-black': TasteFitVerdict(
    productId: 'p-johnnie-black',
    badge: TasteFitBadge.caution,
    headline: '아쉬운 PICK !',
    tags: <String>['#스모키'],
    sentence: '스모키한 향이 있어 부담스러우실 수 있어요.',
    levels: <String, int>{'sweetness': 3, 'body': 3, 'finish_length': 3},
  ),
  'p-dassai-45': TasteFitVerdict(
    productId: 'p-dassai-45',
    badge: TasteFitBadge.star,
    headline: '딱 맞는 PICK !',
    tags: <String>['#화사한_과일향'],
    sentence: '화사한 과일 향이 취향에 잘 맞아요.',
    levels: <String, int>{'sweetness': 3, 'acidity': 2, 'body': 2},
  ),
};

class _TasteFit implements TasteFitGateway {
  @override
  Future<TasteFitResponse> judge(List<String> productIds) async =>
      TasteFitResponse(
        hasCards: true,
        verdicts: <String, TasteFitVerdict>{
          for (final id in productIds) id: ?_verdicts[id],
        },
      );
}

/// A signed-in account's card service. [hold] keeps the card pending until
/// the test completes it, so the loading state can be drawn.
class _TasteCards implements TasteCardGateway {
  _TasteCards({this.hold});

  final Completer<void>? hold;
  late final TasteCardResult card = _servedCard();

  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequestV1 request,
  ) async {
    await hold?.future;
    return TasteCardFinalOutcome(card);
  }

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) async => card;

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequestV1 request,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteOwnedResult(String resultId) async {}
}

class _Notes implements RecordNoteGateway {
  @override
  Future<String> loadNote(String recordId) async => '';

  @override
  Future<void> saveNote({
    required String recordId,
    required String note,
  }) async {}
}

Future<ProfileSummary> _noCardsYet() async =>
    const ProfileSummary(cardCount: 0, savedArticleCount: 0, likedCardCount: 0);

// ---------------------------------------------------------------------------
// Driving
// ---------------------------------------------------------------------------

/// Opens the app at [route] (or at app entry when null) with the fakes.
Future<void> _pumpApp(
  WidgetTester tester,
  Size size, {
  AppRoute? route,
  FakeSocialAuthGateway? socialAuth,
  FakeAccountCompletionGateway? accountCompletion,
  TasteCardGateway? tasteCards,
}) async {
  useViewport(tester, size);
  const channel = MethodChannel('soolgyul/debug-screen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => route?.debugScreen);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  await tester.pumpWidget(
    App(
      socialAuthGateway: socialAuth,
      accountCompletionGateway: accountCompletion,
      profileSummaryLoader: _noCardsYet,
      catalogSearchGateway: _Catalog(),
      tasteCardGateway: tasteCards ?? _TasteCards(),
      tasteFitGateway: _TasteFit(),
      tasteLettersGateway: _Letters(),
      nextDrinkGuidesGateway: _Guides(),
      recordNoteGateway: _Notes(),
      sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey<String>(key));

/// Taps the widget keyed [key]; a missing key lists the keys on screen
/// that share its first part, to make a changed key easy to find.
Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = _key(key);
  if (finder.evaluate().isEmpty) {
    final prefix = key.split(':').first;
    final keys = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(prefix),
        )
        .evaluate()
        .map((element) => (element.widget.key! as ValueKey<String>).value)
        .toSet();
    fail('No widget keyed $key; on screen: $keys');
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Types into the screen's search field and waits out its debounce.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _scrollToTop(WidgetTester tester) async {
  for (final element in find.byType(Scrollable).evaluate()) {
    final position = (element as StatefulElement).state as ScrollableState;
    if (position.position.axis == Axis.vertical) {
      position.position.jumpTo(0);
    }
  }
  await tester.pumpAndSettle();
}

/// Draws the screen as it is this frame, without settling: for states with
/// a running spinner, which never settle.
Future<void> _snapNow(WidgetTester tester, String name) async {
  final root = tester.binding.rootElement!;
  final bytes = await tester.runAsync(() async {
    final image = await captureImage(root);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('${guardOut.path}/$name.png').writeAsBytesSync(bytes!);
}

/// The drink-name step: search, pick [drink], go on to the questions.
/// With [snapName] the results and the picked drink are drawn.
Future<void> _pickDrink(
  WidgetTester tester,
  String query,
  String drink, {
  String Function(String step)? snapName,
}) async {
  await _search(tester, query);
  if (snapName != null) await snap(tester, snapName('Results'));
  await _tapText(tester, drink);
  if (snapName != null) await _snapPage(tester, snapName('Selected'));
  await _tapText(tester, '다음');
}

/// Draws the whole page from its top, whatever an earlier tap scrolled.
Future<void> _snapPage(WidgetTester tester, String name) async {
  await _scrollToTop(tester);
  await snapScrolled(tester, name);
}

/// Scrolls the result card until the lazily built [key] is on screen.
Future<void> _scrollCardTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    _key(key),
    200,
    scrollable: find
        .descendant(
          of: _key('onboarding-page-scroll'),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// Answers every question quickly: revisit, one aroma, tastes, SKIP the
/// rest. Leaves the last question submitted.
Future<void> _answerQuickly(WidgetTester tester) async {
  await _tapKey(tester, 'revisit:wantAgain');
  await _tapKey(tester, 'sensory-next');
  await _tapKey(tester, 'notice:aroma:cherry');
  await _tapKey(tester, 'sensory-next');
  await answerAllTastesFine(tester);
  await _tapKey(tester, 'mouthfeel:unsure');
  // The last answer submits; the pending card's spinner never settles.
  await tester.ensureVisible(_key('finish:unsure'));
  await tester.pumpAndSettle();
  await tester.tap(_key('finish:unsure'));
  await tester.pump();
}

/// Fills the post-login setup: nickname, two interests, a typed birth date,
/// gender and the required agreements.
Future<void> _fillProfileSetup(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, '술결러');
  await tester.pump();
  await _tapText(tester, '와인');
  await _tapText(tester, '위스키');
  // The picker opens on a year that moves with today's date, so the date
  // is typed in its text mode instead.
  await _tapKey(tester, 'birth-date-field');
  final dialog = tester.element(find.byType(DatePickerDialog));
  final localizations = MaterialLocalizations.of(dialog);
  await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextField),
    ),
    localizations.formatCompactDate(DateTime(1995, 5, 17)),
  );
  await tester.pump();
  await tester.tap(find.text('확인').last);
  await tester.pumpAndSettle();
  await pickGender(tester);
  for (final key in <String>[
    'adult-agreement-row',
    'terms-agreement-row',
    'privacy-agreement-row',
  ]) {
    await _tapKey(tester, key);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    // Each scenario looks the suggested drinks up itself, so none depends on
    // the order the scenarios run in.
    // ignore: invalid_use_of_visible_for_testing_member
    SuggestedDrinks.clear();
    // A focused field draws its cursor solid instead of blinking on a timer.
    EditableText.debugDeterministicCursor = true;
  });
  tearDown(() => EditableText.debugDeterministicCursor = false);

  for (final MapEntry(key: device, value: size) in guardViewports.entries) {
    testWidgets('onboarding.profileSetup.$device', (tester) async {
      final auth = FakeSocialAuthGateway();
      addTearDown(auth.close);
      await _pumpApp(
        tester,
        size,
        socialAuth: auth,
        accountCompletion: FakeAccountCompletionGateway(),
      );
      auth.emit(SocialAuthSessionEvent.noSession);
      await tester.pumpAndSettle();
      await _tapKey(tester, 'kakao-login-button');
      await _fillProfileSetup(tester);
      await _snapPage(tester, 'onboarding.profileFilled.$device');
      await _scrollToTop(tester);
      await _tapKey(tester, 'complete-signup-button');
      // The new account has no card yet: the first record starts.
      await _snapPage(tester, 'onboarding.welcomeAfterSignup.$device');
    });

    testWidgets('onboarding.search.$device', (tester) async {
      await _pumpApp(tester, size, route: AppRoute.onboardingWelcome);
      await startOnboarding(tester);
      await _snapPage(tester, 'onboarding.searchSuggestions.$device');
      await _pickDrink(
        tester,
        '몬테스',
        '몬테스 알파 까베르네 소비뇽',
        snapName: (step) => 'onboarding.search$step.$device',
      );
      await _snapPage(tester, 'onboarding.revisit.$device');
    });

    testWidgets('onboarding.questions.$device', (tester) async {
      await _pumpApp(tester, size, route: AppRoute.onboardingWelcome);
      await startOnboarding(tester);
      await _pickDrink(tester, '몬테스', '몬테스 알파 까베르네 소비뇽');
      await _tapKey(tester, 'revisit:wouldAcceptAgain');
      await _snapPage(tester, 'onboarding.revisitSelected.$device');
      await _tapKey(tester, 'sensory-next');
      // One tap likes an aroma, a second makes it a burden.
      await _tapKey(tester, 'notice:aroma:cherry');
      await _tapKey(tester, 'notice:aroma:vanilla');
      await _tapKey(tester, 'notice:aroma:smoke');
      await _tapKey(tester, 'notice:aroma:smoke');
      await _snapPage(tester, 'onboarding.aromaSelected.$device');
      await _tapKey(tester, 'sensory-next');
      await _tapKey(tester, 'reaction:taste:acidity:liked');
      await _tapKey(tester, 'reason:taste:acidity:harmony');
      await _tapKey(tester, 'reaction:taste:sweetness:disliked');
      await _tapKey(tester, 'reason:taste:sweetness:too_strong');
      await _snapPage(tester, 'onboarding.tasteReasons.$device');
      await _tapKey(tester, 'sensory-next');
      await _tapKey(tester, 'judge:mouthfeel:light:liked');
      await _tapKey(tester, 'reaction:mouthfeel:heavy:liked');
      await _tapKey(tester, 'reaction:mouthfeel:warmth:disliked');
      await _snapPage(tester, 'onboarding.mouthfeel.$device');
      await _tapKey(tester, 'sensory-next');
      await _tapKey(tester, 'finish:pleasantLength');
      await _tapKey(tester, 'finish:heavy');
      await _snapPage(tester, 'onboarding.finish.$device');
    });

    testWidgets('onboarding.card.$device', (tester) async {
      final hold = Completer<void>();
      await _pumpApp(
        tester,
        size,
        route: AppRoute.onboardingWelcome,
        tasteCards: _TasteCards(hold: hold),
      );
      await startOnboarding(tester);
      await _pickDrink(tester, '몬테스', '몬테스 알파 까베르네 소비뇽');
      await _answerQuickly(tester);
      await tester.pump(const Duration(seconds: 1));
      await _snapNow(tester, 'onboarding.cardLoading.$device');
      hold.complete();
      await tester.pumpAndSettle();
      await _snapPage(tester, 'onboarding.card.$device');
      await _scrollToTop(tester);
      await tester.tap(_key('taste-card-tag-term-복숭아향'));
      await tester.pumpAndSettle();
      await snap(tester, 'onboarding.cardTagTerm.$device');
      await _tapKey(tester, 'term-tooltip-close');
      await _scrollCardTo(tester, 'taste-card-toggle');
      await _tapKey(tester, 'taste-card-toggle');
      await _snapPage(tester, 'onboarding.cardExpanded.$device');
      await _scrollCardTo(tester, 'taste-card-term-산미');
      await _tapKey(tester, 'taste-card-term-산미');
      await snap(tester, 'onboarding.cardTerm.$device');
    });

    testWidgets('record.flow.$device', (tester) async {
      await _pumpApp(tester, size, route: AppRoute.home);
      await _tapText(tester, '기록하기');
      await _pickDrink(
        tester,
        '닷사이',
        '닷사이 준마이 다이긴죠 45',
        snapName: (step) => 'record.search$step.$device',
      );
      await _tapKey(tester, 'revisit:wantAgain');
      await _tapKey(tester, 'sensory-next');
      await _snapPage(tester, 'record.aroma.$device');
      await _tapKey(tester, 'aroma-search:open');
      await tester.enterText(_key('sensory-aroma-search'), '바닐라');
      await tester.pumpAndSettle();
      await snap(tester, 'record.aromaSearch.$device');
      await _tapKey(tester, 'search:aroma:vanilla');
      await _tapKey(tester, 'aroma-search:done');
      await _tapKey(tester, 'notice:aroma:melon');
      await _snapPage(tester, 'record.aromaPicked.$device');
      await _tapKey(tester, 'sensory-next');
      await answerAllTastesFine(tester);
      await _tapKey(tester, 'mouthfeel:unsure');
      await _tapKey(tester, 'finish:clean');
      await _tapKey(tester, 'sensory-next');
      await _snapPage(tester, 'record.card.$device');
      await _tapKey(tester, 'taste-card-more');
      await snap(tester, 'record.cardMenu.$device');
    });

    testWidgets('home.data.$device', (tester) async {
      await _pumpApp(tester, size, route: AppRoute.home);
      await _snapPage(tester, 'home.data.$device');
      final carousel = find.byKey(const Key('next-drink-carousel'));
      await tester.ensureVisible(carousel);
      await tester.pumpAndSettle();
      // A swipe draws the next, taller slide inside the shown slide's
      // height for a few frames (a debug overflow); jumping skips those.
      final pager = tester.widget<PageView>(carousel).controller!;
      pager.jumpToPage(1);
      await tester.pumpAndSettle();
      await snap(tester, 'home.guideSlide2.$device');
      pager.jumpToPage(2);
      await tester.pumpAndSettle();
      await snap(tester, 'home.guideSlide3.$device');
      await _scrollToTop(tester);
      await _tapText(tester, '나의 취향 조각');
      await _snapPage(tester, 'home.letters.$device');
      await _tapText(tester, '내 취향 여정 전체보기');
      await snap(tester, 'home.lettersJourney.$device');
    });

    testWidgets('tasteFit.flow.$device', (tester) async {
      await _pumpApp(tester, size, route: AppRoute.home);
      await _tapKey(tester, 'home-taste-fit-entry');
      await snap(tester, 'tasteFit.suggestions.$device');
      await _search(tester, '소비뇽');
      await snap(tester, 'tasteFit.results.$device');
      await _tapText(tester, '클라우디 베이 소비뇽 블랑');
      await _snapPage(tester, 'tasteFit.detailStar.$device');
      await _scrollToTop(tester);
      await _tapKey(tester, 'taste-fit-fact-grape-소비뇽 블랑');
      await snap(tester, 'tasteFit.factTerm.$device');
      await _tapKey(tester, 'term-tooltip-close');
      await tester.tap(find.byTooltip('뒤로가기'));
      await tester.pumpAndSettle();
      await _tapText(tester, '몬테스 알파 까베르네 소비뇽');
      await _snapPage(tester, 'tasteFit.detailCaution.$device');
      await tester.tap(find.byTooltip('뒤로가기'));
      await tester.pumpAndSettle();
      await _tapText(tester, '소비뇽 블랑 하우스 와인');
      await _snapPage(tester, 'tasteFit.detailNoVerdict.$device');
    });
  }
}
