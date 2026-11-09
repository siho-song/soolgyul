// Temporary: refactor guard. Deleted with refactor_guard/ when the refactor ends.
//
// Draws the 취향 tab, My Page, saved cards and articles, explore and an
// article on fixed data, loaded and driven into the states a refactor could
// break, so the refactor can prove it changed no pixel.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_gateway.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart'
    show TasteCardTagKind;
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/profile/data/account_deletion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/liked_cards_gateway.dart';
import 'package:soolgyul/src/features/profile/data/marketing_consent_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import '../test/support/app_test_harness.dart';
import 'snap.dart';

// ---------------------------------------------------------------------------
// Harness

Future<void> pumpApp(
  WidgetTester tester,
  AppRoute route,
  Size size,
  App app,
) async {
  useViewport(tester, size);
  const channel = MethodChannel('soolgyul/debug-screen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => route.debugScreen);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// One test per device; [body] gets the viewport and the picture name.
void scenario(
  String name,
  Future<void> Function(WidgetTester tester, Size size, String shot) body,
) {
  for (final MapEntry(key: device, value: size) in guardViewports.entries) {
    testWidgets(
      '$name.$device',
      (tester) => body(tester, size, '$name.$device'),
    );
  }
}

// ---------------------------------------------------------------------------
// 취향 tab

HistoryRecord _record(
  String id,
  DateTime at, {
  required String title,
  String category = 'wine',
  String label = '와인',
  List<HistoryTag> tags = const <HistoryTag>[],
  String? summary,
  String? note,
  String? imageUrl,
}) => HistoryRecord(
  resultId: id,
  title: title,
  categoryKey: category,
  categoryLabel: label,
  recordedAt: at,
  tags: tags,
  summary: summary,
  note: note,
  imageUrl: imageUrl,
);

const _longLine =
    '싱그러운 체리 향과 침샘을 자극하는 깔끔한 산미는 반갑지만, 입안을 꽉 조이는 떫은맛과 '
    '입안을 꽉 채우는 묵직함, 확 올라오는 알코올 열감은 아직 조금 버거워요. 다음엔 떫은맛이 '
    '한 톤 부드러운 술로 가볼까요? 마무리는 깔끔하게 떨어져서 좋았어요.';

const _longNote =
    '친구 집들이에서 마셨다. 처음엔 시큼했는데 잔에 두고 십 분쯤 지나니 꽃향이 올라왔다. '
    '치즈랑 같이 먹으니 훨씬 부드러웠고, 다음엔 조금 더 차갑게 마셔 보고 싶다.';

final _juneRecords = <HistoryRecord>[
  _record(
    'r-margaux',
    DateTime(2026, 6, 3, 20, 10),
    title: '샤토 마고 2015',
    tags: const <HistoryTag>[
      HistoryTag('산미', TasteCardTagKind.liked),
      HistoryTag('과일향', TasteCardTagKind.liked),
      HistoryTag('떫은맛', TasteCardTagKind.less),
    ],
    summary: '산미가 반가웠어요.',
    note: '생일 저녁, 다음에 또.',
  ),
  _record(
    'r-laphroaig',
    DateTime(2026, 6, 3, 22, 40),
    title: '라프로익 10년',
    category: 'whisky',
    label: '위스키',
    tags: const <HistoryTag>[
      HistoryTag('스모키', TasteCardTagKind.liked),
      HistoryTag('알코올 열감', TasteCardTagKind.burden),
    ],
    summary: '향긋한 바닐라 향과 깔끔한 마무리까지 마음에 쏙 들었어요.',
  ),
  _record(
    'r-dassai',
    DateTime(2026, 6, 11, 19),
    title: '닷사이 45 준마이 다이긴조 야마다니시키 한정 병입',
    category: 'sake',
    label: '사케',
    tags: const <HistoryTag>[
      HistoryTag('단맛', TasteCardTagKind.more),
      HistoryTag('산미', TasteCardTagKind.liked),
    ],
    summary: '은은한 멜론 향이 오래 남았어요.',
    note: _longNote,
  ),
  _record(
    'r-boksoon',
    DateTime(2026, 6, 18, 21, 30),
    title: '복순도가 손막걸리',
    category: 'korean_traditional',
    label: '전통주',
    tags: const <HistoryTag>[
      HistoryTag('탄산감', TasteCardTagKind.liked),
      HistoryTag('바디감', TasteCardTagKind.fine),
      HistoryTag('여운', TasteCardTagKind.less),
      HistoryTag('곡물향', TasteCardTagKind.liked),
    ],
    summary: _longLine,
  ),
  _record(
    'r-cloudy',
    DateTime(2026, 6, 20, 20, 5),
    title: '클라우디 베이 소비뇽 블랑',
    imageUrl: 'https://example.invalid/bottle.png',
    tags: const <HistoryTag>[HistoryTag('상큼함', TasteCardTagKind.liked)],
  ),
  _record(
    'r-highball',
    DateTime(2026, 6, 24, 0, 15),
    title: '하이볼',
    category: 'other',
    label: '기타',
  ),
];

class _History implements PreferenceHistoryGateway {
  _History(this.records, {this.fail = false});

  final List<HistoryRecord> records;
  final bool fail;

  @override
  Future<DateTime?> latestRecordedAt() async => DateTime(2026, 6, 24, 0, 15);

  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async {
    if (fail) throw StateError('offline');
    return <HistoryRecord>[
      for (final record in records)
        if (record.recordedAt.year == month.year &&
            record.recordedAt.month == month.month)
          record,
    ];
  }
}

Future<void> pumpPreference(
  WidgetTester tester,
  Size size, {
  bool fail = false,
}) => pumpApp(
  tester,
  AppRoute.preference,
  size,
  App(
    preferenceHistoryGateway: _History(_juneRecords, fail: fail),
    sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
  ),
);

void preferenceScenarios() {
  scenario('preference.month', (tester, size, shot) async {
    await pumpPreference(tester, size);
    await snapScrolled(tester, shot);
  });

  scenario('preference.carouselScrolled', (tester, size, shot) async {
    await pumpPreference(tester, size);
    final carousel = byKey('history-day-carousel');
    await tester.ensureVisible(carousel);
    await tester.pumpAndSettle();
    for (var page = 0; page < 3; page++) {
      await tester.drag(carousel, const Offset(-200, 0));
      await tester.pumpAndSettle();
    }
    await snapScrolled(tester, shot);
  });

  scenario('preference.dayWithMemo', (tester, size, shot) async {
    await pumpPreference(tester, size);
    await tapVisible(tester, byKey('history-day-3'));
    await snapScrolled(tester, shot);
  });

  scenario('preference.memoBalloon', (tester, size, shot) async {
    await pumpPreference(tester, size);
    await tapVisible(tester, byKey('history-day-3'));
    await tapVisible(tester, byKey('history-record-note-r-margaux'));
    await snap(tester, shot);
  });

  scenario('preference.memoBalloonLong', (tester, size, shot) async {
    await pumpPreference(tester, size);
    await tapVisible(tester, byKey('history-day-11'));
    await tapVisible(tester, byKey('history-record-note-r-dassai'));
    await snap(tester, shot);
  });

  scenario('preference.longLineFolded', (tester, size, shot) async {
    await pumpPreference(tester, size);
    await tapVisible(tester, byKey('history-day-18'));
    await snapScrolled(tester, shot);
  });

  scenario('preference.longLineUnfolded', (tester, size, shot) async {
    await pumpPreference(tester, size);
    await tapVisible(tester, byKey('history-day-18'));
    await tapVisible(tester, byKey('history-record-summary-toggle'));
    await snapScrolled(tester, shot);
  });

  scenario('preference.photoFailed', (tester, size, shot) async {
    await pumpPreference(tester, size);
    await tapVisible(tester, byKey('history-day-20'));
    await snapScrolled(tester, shot);
  });

  scenario('preference.emptyDay', (tester, size, shot) async {
    await pumpPreference(tester, size);
    await tapVisible(tester, byKey('history-day-5'));
    await snapScrolled(tester, shot);
  });

  scenario('preference.emptyMonth', (tester, size, shot) async {
    await pumpPreference(tester, size);
    await tapVisible(tester, find.byTooltip('이전 달'));
    await snapScrolled(tester, shot);
  });

  scenario('preference.loadFailed', (tester, size, shot) async {
    await pumpPreference(tester, size, fail: true);
    await snapScrolled(tester, shot);
  });
}

// ---------------------------------------------------------------------------
// My Page

Future<ProfileSummary> _summary() async => const ProfileSummary(
  cardCount: 27,
  savedArticleCount: 4,
  likedCardCount: 12,
);

Future<ProfileSummary> _failedSummary() async => throw StateError('offline');

class _Consent implements MarketingConsentGateway {
  @override
  Future<bool> load() async => true;

  @override
  Future<bool> save(bool accepted) async => accepted;
}

class _Deletion implements AccountDeletionGateway {
  @override
  Future<AccountDeletionStatus> fetchStatus() async =>
      const AccountDeletionStatus(state: 'active');

  @override
  Future<void> requestDeletion() async {}

  @override
  Future<void> restore() async {}
}

Future<void> pumpProfile(
  WidgetTester tester,
  Size size, {
  ProfileSummaryLoader loader = _summary,
  AppRoute route = AppRoute.profile,
}) => pumpApp(
  tester,
  route,
  size,
  App(
    profileSummaryLoader: loader,
    marketingConsentGateway: _Consent(),
    accountDeletionGateway: _Deletion(),
    sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
  ),
);

final _nicknameField = find.descendant(
  of: byKey('profile-nickname-field'),
  matching: find.byType(EditableText),
);

void profileScenarios() {
  scenario('profile.counts', (tester, size, shot) async {
    await pumpProfile(tester, size);
    await snapScrolled(tester, shot);
  });

  scenario('profile.countsFailed', (tester, size, shot) async {
    await pumpProfile(tester, size, loader: _failedSummary);
    await snapScrolled(tester, shot);
  });

  scenario('profile.nicknameSheet', (tester, size, shot) async {
    await pumpProfile(tester, size);
    await tapVisible(tester, byKey('profile-nickname-edit'));
    await snap(tester, shot);
  });

  scenario('profile.nicknameInvalid', (tester, size, shot) async {
    await pumpProfile(tester, size);
    await tapVisible(tester, byKey('profile-nickname-edit'));
    await tester.enterText(_nicknameField, '술 결!');
    await tester.pumpAndSettle();
    await snap(tester, shot);
  });

  scenario('profile.nicknameSaved', (tester, size, shot) async {
    await pumpProfile(tester, size);
    await tapVisible(tester, byKey('profile-nickname-edit'));
    await tester.enterText(_nicknameField, '술결러버Soolgyul');
    await tester.pumpAndSettle();
    await tapVisible(tester, byKey('profile-save-button'));
    await snapScrolled(tester, shot);
  });

  scenario('profile.interestSheet', (tester, size, shot) async {
    await pumpProfile(tester, size);
    await tapVisible(tester, byKey('profile-interest-settings'));
    await tester.tap(byKey('profile-drink-와인'));
    await tester.pumpAndSettle();
    await snap(tester, shot);
  });

  scenario('profile.interestsSaved', (tester, size, shot) async {
    await pumpProfile(tester, size);
    await tapVisible(tester, byKey('profile-interest-settings'));
    await tester.tap(byKey('profile-drink-와인'));
    await tester.tap(byKey('profile-drink-위스키'));
    await tester.pumpAndSettle();
    await tapVisible(tester, byKey('profile-drink-complete'));
    await snapScrolled(tester, shot);
  });

  scenario('profile.policy', (tester, size, shot) async {
    await pumpProfile(tester, size, route: AppRoute.policy);
    await snapScrolled(tester, shot);
  });

  scenario('profile.signOutSheet', (tester, size, shot) async {
    await pumpProfile(tester, size, route: AppRoute.policy);
    await tapVisible(tester, byKey('policy-sign-out'));
    await snap(tester, shot);
  });

  scenario('profile.deletionSheet', (tester, size, shot) async {
    await pumpProfile(tester, size, route: AppRoute.policy);
    await tapVisible(tester, byKey('policy-account-deletion'));
    await snap(tester, shot);
  });
}

// ---------------------------------------------------------------------------
// Saved cards

final _likedCards = <LikedCard>[
  LikedCard(
    id: 'c1',
    title: '샤토 마고 2015',
    summary: '산미가 반가웠고 떫은맛은 조금 버거웠어요.',
    category: 'wine',
    recordedAt: DateTime(2026, 9, 21),
    likedAt: DateTime(2026, 9, 21),
  ),
  LikedCard(
    id: 'c2',
    title: '라프로익 10년 캐스크 스트렝스 배치 15 한정판',
    summary:
        '스모키한 향이 처음엔 낯설었지만 마무리가 길게 남아 다시 찾게 돼요. '
        '물을 몇 방울 떨어뜨리니 바닐라와 바다 내음이 함께 올라왔어요.',
    category: 'whisky',
    recordedAt: DateTime(2026, 9, 14),
    likedAt: DateTime(2026, 9, 14),
    imageUrl: 'https://example.invalid/laphroaig.png',
  ),
  LikedCard(
    id: 'c3',
    title: '닷사이 45',
    summary: '은은한 멜론 향.',
    category: 'sake',
    recordedAt: DateTime(2026, 8, 30),
    likedAt: DateTime(2026, 8, 30),
  ),
  LikedCard(
    id: 'c4',
    title: '복순도가 손막걸리',
    summary: '탄산이 톡톡 터지고 곡물 향이 고소했어요.',
    category: 'korean_traditional',
    recordedAt: DateTime(2026, 8, 2),
    likedAt: DateTime(2026, 8, 2),
  ),
  LikedCard(
    id: 'c5',
    title: '클라우디 베이 소비뇽 블랑',
    summary: '풀내음과 자몽 향이 상큼했어요.',
    category: 'wine',
    recordedAt: DateTime(2026, 7, 11),
    likedAt: DateTime(2026, 7, 11),
  ),
];

class _Likes implements LikedCardsGateway {
  _Likes(this.rows);

  final List<LikedCard> rows;

  @override
  Future<LikedCardsPage> fetch({
    String? category,
    bool latestFirst = true,
    int offset = 0,
  }) async {
    var filtered = rows
        .where((row) => category == null || row.category == category)
        .toList();
    if (!latestFirst) filtered = filtered.reversed.toList();
    return LikedCardsPage(
      cards: filtered.skip(offset).take(30).toList(),
      total: filtered.length,
    );
  }

  @override
  Future<bool> isLiked(String cardId) async =>
      rows.any((row) => row.id == cardId);

  @override
  Future<void> like(String cardId, {DateTime? likedAt}) async {}

  @override
  Future<void> unlike(String cardId) async =>
      rows.removeWhere((row) => row.id == cardId);
}

Future<void> pumpSavedCards(
  WidgetTester tester,
  Size size,
  List<LikedCard> rows,
) => pumpApp(
  tester,
  AppRoute.savedCards,
  size,
  App(
    likedCardsGateway: _Likes(List<LikedCard>.of(rows)),
    profileSummaryLoader: _summary,
    sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
  ),
);

void savedCardsScenarios() {
  scenario('savedCards.list', (tester, size, shot) async {
    await pumpSavedCards(tester, size, _likedCards);
    await snapScrolled(tester, shot);
  });

  scenario('savedCards.wineOldestFirst', (tester, size, shot) async {
    await pumpSavedCards(tester, size, _likedCards);
    await tapVisible(tester, find.text('와인').first);
    await tapVisible(tester, find.text('최신순'));
    await snapScrolled(tester, shot);
  });

  scenario('savedCards.unliked', (tester, size, shot) async {
    await pumpSavedCards(tester, size, _likedCards);
    await tapVisible(tester, find.byTooltip('좋아요 취소').first);
    await snapScrolled(tester, shot);
  });

  scenario('savedCards.empty', (tester, size, shot) async {
    await pumpSavedCards(tester, size, const <LikedCard>[]);
    await snapScrolled(tester, shot);
  });
}

// ---------------------------------------------------------------------------
// Explore, saved articles and an article

EditorialMediaAsset _photo(String id, int order, String file) =>
    EditorialMediaAsset(
      id: '73000000-0000-4000-8000-0000000000$id$order',
      storageBucket: 'flutter-assets',
      storageObjectPath: 'assets/component_assets/explore_feed/$file',
      sortOrder: order,
    );

EditorialArticle _post(
  String id,
  String body, {
  required List<String> interests,
  required List<String> photos,
  required DateTime publishedAt,
  String? instagramUrl,
}) => EditorialArticle(
  id: '72000000-0000-4000-8000-0000000000$id',
  body: body,
  publishedAt: publishedAt,
  mediaAssets: <EditorialMediaAsset>[
    for (var index = 0; index < photos.length; index++)
      _photo(id, index, photos[index]),
  ],
  interestKeys: interests,
  instagramUrl: instagramUrl,
);

final _acidity = _post(
  '01',
  '산미는 이런 느낌이에요\n\n'
      '레몬을 한 입 베어 문 것처럼 침이 고이는 느낌, 그게 와인의 산미예요. '
      '산미가 높은 와인은 기름진 음식과 잘 어울리고, 차갑게 마시면 더 또렷해져요.\n\n'
      '처음이라면 소비뇽 블랑이나 리슬링처럼 산미가 분명한 화이트 와인부터 시작해 보세요.',
  interests: const <String>['wine'],
  photos: const <String>[
    'beginner_wine_acidity.png',
    'white_wine.webp',
    'date_wine.webp',
  ],
  publishedAt: DateTime(2026, 8, 18),
  instagramUrl: 'https://www.instagram.com/p/example/',
);
final _vanilla = _post(
  '02',
  '위스키의 바닐라 향은 오크통에서 와요',
  interests: const <String>['whisky'],
  photos: const <String>['beginner_whisky_vanilla.png', 'featured_whisky.webp'],
  publishedAt: DateTime(2026, 8, 16),
);
final _sakeTemperature = _post(
  '03',
  '사케는 온도에 따라 맛이 달라져요',
  interests: const <String>['sake'],
  photos: const <String>['beginner_sake_temperature.png'],
  publishedAt: DateTime(2026, 8, 12),
);
final _naturalWine = _post(
  '04',
  '요즘 내추럴 와인이 주목받는 이유',
  interests: const <String>['wine'],
  photos: const <String>['trend_natural_wine.png'],
  publishedAt: DateTime(2026, 8, 9),
);
final _traditional = _post(
  '05',
  '막걸리와 약주, 무엇이 다를까요',
  interests: const <String>['korean_traditional'],
  photos: const <String>['traditional.webp'],
  publishedAt: DateTime(2026, 8, 3),
);
final _featuredWhisky = _post(
  '06',
  '같은 위스키도 잔에 따라 맛이 달라져요',
  interests: const <String>['whisky', 'wine'],
  photos: const <String>['featured_whisky.webp'],
  publishedAt: DateTime(2026, 7, 28),
);
final _noPhoto = _post(
  '07',
  '집에서 즐기기 좋은 가벼운 한 잔',
  interests: const <String>[],
  photos: const <String>[],
  publishedAt: DateTime(2026, 7, 20),
);

final _published = <EditorialArticle>[
  _acidity,
  _vanilla,
  _sakeTemperature,
  _naturalWine,
  _traditional,
  _featuredWhisky,
  _noPhoto,
];

final _saved = <EditorialArticle>[
  _acidity.copyWithSavedAt(DateTime(2026, 9, 1)),
  _traditional.copyWithSavedAt(DateTime(2026, 8, 28)),
  _vanilla.copyWithSavedAt(DateTime(2026, 8, 20)),
];

class _Editorial implements EditorialArticleGateway {
  _Editorial({this.saved = const <EditorialArticle>[]});

  final List<EditorialArticle> saved;

  @override
  Future<List<EditorialArticle>> fetchPublishedArticles() async => _published;

  @override
  Future<List<EditorialArticle>> fetchSavedArticles() async => saved;

  @override
  Future<void> saveArticle(String articleId) async {}

  @override
  Future<void> unsaveArticle(String articleId) async {}
}

Future<void> pumpEditorial(
  WidgetTester tester,
  Size size,
  AppRoute route, {
  List<EditorialArticle> saved = const <EditorialArticle>[],
}) => pumpApp(
  tester,
  route,
  size,
  App(
    editorialArticleGateway: _Editorial(saved: saved),
    profileSummaryLoader: _summary,
    sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
  ),
);

Finder _articleCard(EditorialArticle article) =>
    byKey('explore-article-${article.id}');

void exploreScenarios() {
  scenario('explore.feed', (tester, size, shot) async {
    await pumpEditorial(tester, size, AppRoute.explore);
    await snapScrolled(tester, shot);
  });

  scenario('explore.tagWhisky', (tester, size, shot) async {
    await pumpEditorial(tester, size, AppRoute.explore);
    await tapVisible(tester, byKey('explore-tag-whisky'));
    await snapScrolled(tester, shot);
  });

  scenario('explore.tagSake', (tester, size, shot) async {
    await pumpEditorial(tester, size, AppRoute.explore);
    await tapVisible(tester, byKey('explore-tag-sake'));
    await snapScrolled(tester, shot);
  });

  scenario('editorial.article', (tester, size, shot) async {
    await pumpEditorial(tester, size, AppRoute.explore, saved: _saved);
    await tapVisible(tester, _articleCard(_acidity));
    await snapScrolled(tester, shot);
  });

  scenario('editorial.gallerySwiped', (tester, size, shot) async {
    await pumpEditorial(tester, size, AppRoute.explore);
    await tapVisible(tester, _articleCard(_acidity));
    final gallery = byKey('editorial-article-gallery');
    for (var page = 0; page < 2; page++) {
      await tester.drag(gallery, const Offset(-300, 0));
      await tester.pumpAndSettle();
    }
    await snap(tester, shot);
  });

  scenario('editorial.relatedScrolled', (tester, size, shot) async {
    await pumpEditorial(tester, size, AppRoute.explore);
    await tapVisible(tester, _articleCard(_vanilla));
    final related = byKey('editorial-article-related');
    await tester.ensureVisible(related);
    await tester.pumpAndSettle();
    await tester.drag(related, const Offset(-400, 0));
    await tester.pumpAndSettle();
    await snap(tester, shot);
  });

  scenario('editorial.noPhoto', (tester, size, shot) async {
    await pumpEditorial(tester, size, AppRoute.explore);
    await tapVisible(tester, _articleCard(_noPhoto));
    await snapScrolled(tester, shot);
  });

  scenario('savedArticles.list', (tester, size, shot) async {
    await pumpEditorial(tester, size, AppRoute.savedArticles, saved: _saved);
    await snapScrolled(tester, shot);
  });

  scenario('savedArticles.tagWine', (tester, size, shot) async {
    await pumpEditorial(tester, size, AppRoute.savedArticles, saved: _saved);
    await tapVisible(tester, byKey('explore-tag-wine'));
    await snapScrolled(tester, shot);
  });
}

void main() {
  // A focused field draws its caret steadily instead of blinking.
  EditableText.debugDeterministicCursor = true;
  preferenceScenarios();
  profileScenarios();
  savedCardsScenarios();
  exploreScenarios();
}
