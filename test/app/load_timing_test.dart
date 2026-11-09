import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_gateway.dart';
import 'package:soolgyul/src/features/home/data/next_drink_guides.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/profile/data/liked_cards_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';

/// Every read the tabs make, in order, so a change in when the app asks the
/// server (on each visit, once per session, after a change) shows here.
final _asked = <String>[];

class _Letters implements TasteLettersGateway {
  @override
  Future<TasteLettersSnapshot> load() async {
    _asked.add('letters');
    return const TasteLettersSnapshot();
  }
}

class _Guides implements NextDrinkGuidesGateway {
  @override
  Future<List<NextDrinkGuide>> load() async {
    _asked.add('guides');
    return const <NextDrinkGuide>[];
  }
}

class _History implements PreferenceHistoryGateway {
  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async {
    _asked.add('month');
    return const <HistoryRecord>[];
  }

  @override
  Future<DateTime?> latestRecordedAt() async {
    _asked.add('latest');
    return null;
  }
}

const _resultId = '20000000-0000-4000-8000-000000000009';

/// 취향 with one record this month, which the reader opens.
class _OneRecordHistory implements PreferenceHistoryGateway {
  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async {
    _asked.add('month');
    final now = DateTime.now();
    return <HistoryRecord>[
      HistoryRecord(
        resultId: _resultId,
        title: '샤토 테스트',
        categoryKey: 'wine',
        categoryLabel: '와인',
        recordedAt: DateTime(now.year, now.month, now.day, 12),
      ),
    ];
  }

  @override
  Future<DateTime?> latestRecordedAt() async {
    _asked.add('latest');
    return null;
  }
}

class _Cards implements TasteCardGateway {
  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) async {
    _asked.add('card');
    return TasteCardResult(
      resultId: resultId,
      recordId: '30000000-0000-4000-8000-000000000009',
      snapshotRef: designTasteCard.snapshotRef,
      ownership: TasteCardOwnership.saved,
      viewData: designTasteCard,
    );
  }

  @override
  Future<void> deleteOwnedResult(String resultId) async => _asked.add('delete');

  @override
  Future<TasteCardCreateOutcome> create(CreateTasteCardResultRequestV1 r) =>
      throw UnimplementedError();

  @override
  Future<TasteCardResult> convert(AnonymousTasteCardConversionRequestV1 r) =>
      throw UnimplementedError();
}

class _Notes implements RecordNoteGateway {
  @override
  Future<String> loadNote(String recordId) async {
    _asked.add('note');
    return '';
  }

  @override
  Future<void> saveNote({
    required String recordId,
    required String note,
  }) async => _asked.add('save note');
}

class _Liked implements LikedCardsGateway {
  @override
  Future<LikedCardsPage> fetch({
    String? category,
    bool latestFirst = true,
    int offset = 0,
  }) async {
    _asked.add('liked');
    return const LikedCardsPage(cards: <LikedCard>[], total: 0);
  }

  @override
  Future<bool> isLiked(String cardId) async => false;

  @override
  Future<void> unlike(String cardId) async {}

  @override
  Future<void> like(String cardId, {DateTime? likedAt}) async {}
}

class _Editorial implements EditorialArticleGateway {
  static final article = EditorialArticle(
    id: '72000000-0000-4000-8000-000000000001',
    body: '산미가 좋은 와인 이야기',
    publishedAt: DateTime(2026, 8, 18),
    mediaAssets: const <EditorialMediaAsset>[],
    interestKeys: const <String>['wine'],
  );

  @override
  Future<List<EditorialArticle>> fetchPublishedArticles() async {
    _asked.add('articles');
    return <EditorialArticle>[article];
  }

  @override
  Future<List<EditorialArticle>> fetchSavedArticles() async {
    _asked.add('saved articles');
    return const <EditorialArticle>[];
  }

  @override
  Future<void> saveArticle(String articleId) async => _asked.add('save');

  @override
  Future<void> unsaveArticle(String articleId) async => _asked.add('unsave');
}

Future<ProfileSummary> _summary() async {
  _asked.add('summary');
  return const ProfileSummary(
    cardCount: 1,
    savedArticleCount: 2,
    likedCardCount: 3,
  );
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// What was asked since the last call.
List<String> _drain() {
  final asked = List<String>.of(_asked);
  _asked.clear();
  return asked;
}

void main() {
  testWidgets('what the tabs ask the server as the reader moves between them', (
    tester,
  ) async {
    _asked.clear();
    tester.view.physicalSize = defaultAppTestViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('soolgyul/debug-screen');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => AppRoute.home.debugScreen,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      App(
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        tasteLettersGateway: _Letters(),
        nextDrinkGuidesGateway: _Guides(),
        preferenceHistoryGateway: _History(),
        likedCardsGateway: _Liked(),
        profileSummaryLoader: _summary,
        editorialArticleGateway: _Editorial(),
      ),
    );
    await tester.pumpAndSettle();
    final steps = <String, List<String>>{'open home': _drain()};

    await _tab(tester, '취향');
    steps['to 취향'] = _drain();
    await _tab(tester, '마이');
    steps['to 마이'] = _drain();
    final savedCards = find.text('저장한 술결 카드');
    await tester.ensureVisible(savedCards);
    await tester.tap(savedCards);
    await tester.pumpAndSettle();
    steps['open saved cards'] = _drain();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    steps['back to 마이'] = _drain();
    await _tab(tester, '홈');
    steps['back to 홈'] = _drain();
    await _tab(tester, '취향');
    steps['back to 취향'] = _drain();
    await _tab(tester, '마이');
    steps['back to 마이 again'] = _drain();

    // Home, 취향 and My Page ask once and keep what came; they ask again
    // only after a change to what they show. Saved cards are asked each time
    // they open.
    // Saving or unsaving a post changes a count, so the counts load again.
    await _tab(tester, '탐색');
    steps['to 탐색'] = _drain();
    await tester.tap(
      find.byKey(ValueKey<String>('explore-article-${_Editorial.article.id}')),
    );
    await tester.pumpAndSettle();
    steps['open a post'] = _drain();
    await tester.tap(find.byTooltip('게시글 저장'));
    await tester.pumpAndSettle();
    steps['save the post'] = _drain();
    await tester.tap(find.byTooltip('저장 해제'));
    await tester.pumpAndSettle();
    steps['unsave the post'] = _drain();

    expect(steps, <String, List<String>>{
      'open home': ['letters', 'guides'],
      'to 취향': ['latest', 'month'],
      'to 마이': ['summary'],
      'open saved cards': ['liked'],
      'back to 마이': [],
      'back to 홈': [],
      'back to 취향': [],
      'back to 마이 again': [],
      'to 탐색': ['articles'],
      'open a post': ['saved articles', 'articles'],
      'save the post': ['save', 'summary'],
      'unsave the post': ['unsave', 'summary'],
    });
  });

  testWidgets('a saved note and a deleted card reload only what shows them', (
    tester,
  ) async {
    _asked.clear();
    tester.view.physicalSize = defaultAppTestViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('soolgyul/debug-screen');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => AppRoute.home.debugScreen,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      App(
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        tasteLettersGateway: _Letters(),
        nextDrinkGuidesGateway: _Guides(),
        preferenceHistoryGateway: _OneRecordHistory(),
        likedCardsGateway: _Liked(),
        profileSummaryLoader: _summary,
        tasteCardGateway: _Cards(),
        recordNoteGateway: _Notes(),
      ),
    );
    await tester.pumpAndSettle();
    await _tab(tester, '마이');
    await _tab(tester, '취향');
    _drain();

    final record = find.byKey(
      const ValueKey<String>('history-record-$_resultId'),
    );
    await tester.ensureVisible(record);
    await tester.pumpAndSettle();
    await tester.tap(record);
    await tester.pumpAndSettle();
    final steps = <String, List<String>>{'open the card': _drain()};

    await tester.tap(find.byKey(const ValueKey<String>('taste-card-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('taste-card-menu-note')),
    );
    await tester.pumpAndSettle();
    steps['open the note'] = _drain();
    await tester.enterText(
      find.byKey(const ValueKey<String>('taste-card-note-field')),
      '산미가 좋았다',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('taste-card-note-save')),
    );
    await tester.pumpAndSettle();
    steps['save the note'] = _drain();

    // The calendar shows notes; it asks again when 취향 shows next.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    steps['back to 취향 after the note'] = _drain();

    await tester.tap(record);
    await tester.pumpAndSettle();
    _drain();
    await tester.tap(find.byKey(const ValueKey<String>('taste-card-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('taste-card-menu-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('record-delete-confirm')),
    );
    await tester.pumpAndSettle();
    steps['delete the card'] = _drain();
    // Home asks again for what the deleted card fed when it shows next.
    await _tab(tester, '홈');
    steps['to 홈 after the delete'] = _drain();

    expect(steps, <String, List<String>>{
      'open the card': ['card', 'note'],
      'open the note': [],
      'save the note': ['save note'],
      'back to 취향 after the note': ['month'],
      'delete the card': ['delete', 'summary', 'latest', 'month'],
      'to 홈 after the delete': ['letters', 'guides'],
    });
  });
}
