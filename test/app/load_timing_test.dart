import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_gateway.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
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
    // One record, as [_cardCount] says: the home shows its boxes.
    return const TasteLettersSnapshot(
      state: TasteLettersState(axes: {}, recordCount: 1),
    );
  }
}

/// 기록 with [records] in the month shown.
class _History implements PreferenceHistoryGateway {
  _History([this.records = const <HistoryRecord>[]]);

  final List<HistoryRecord> records;

  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async {
    _asked.add('month');
    return records;
  }

  @override
  Future<List<HistoryRecord>> loadAll() async {
    _asked.add('all records');
    return records;
  }

  @override
  Future<DateTime?> latestRecordedAt() async {
    _asked.add('latest');
    return null;
  }
}

const _resultId = '20000000-0000-4000-8000-000000000009';

/// 기록 with one record this month, which the reader opens.
_History _oneRecordHistory() {
  final now = DateTime.now();
  return _History(<HistoryRecord>[
    HistoryRecord(
      resultId: _resultId,
      title: '샤토 테스트',
      categoryKey: 'wine',
      categoryLabel: '와인',
      recordedAt: DateTime(now.year, now.month, now.day, 12),
    ),
  ]);
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
  Future<TasteCardCreateOutcome> create(CreateTasteCardResultRequest r) =>
      throw UnimplementedError();

  @override
  Future<TasteCardResult> convert(AnonymousTasteCardConversionRequest r) =>
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
}

Future<int> _cardCount() async {
  _asked.add('card count');
  return 1;
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
    useTestViewport(tester);
    openAppAtDebugRoute(AppRoute.home);

    await tester.pumpWidget(
      App(
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        tasteLettersGateway: _Letters(),
        preferenceHistoryGateway: _History(),
        cardCountLoader: _cardCount,
        editorialArticleGateway: _Editorial(),
      ),
    );
    await tester.pumpAndSettle();
    final steps = <String, List<String>>{'open home': _drain()};

    await _tab(tester, '기록');
    steps['to 기록'] = _drain();
    await _tab(tester, '내 정보');
    steps['to 마이'] = _drain();
    await _tab(tester, '홈');
    steps['back to 홈'] = _drain();
    await _tab(tester, '기록');
    steps['back to 기록'] = _drain();
    await _tab(tester, '내 정보');
    steps['back to 마이 again'] = _drain();

    // Home and 기록 ask once and keep what came; they ask again only after
    // a change to what they show. 내 정보 asks nothing: it shows what the app
    // already holds.
    await _tab(tester, '피드');
    steps['to 피드'] = _drain();
    await tester.tap(
      find.byKey(ValueKey<String>('explore-article-${_Editorial.article.id}')),
    );
    await tester.pumpAndSettle();
    steps['open a post'] = _drain();

    expect(steps, <String, List<String>>{
      'open home': ['letters'],
      'to 기록': ['latest', 'month'],
      'to 마이': [],
      'back to 홈': [],
      'back to 기록': [],
      'back to 마이 again': [],
      'to 피드': ['articles'],
      'open a post': ['articles'],
    });
  });

  testWidgets(
    'signing in asks behind home for what the other tabs show first',
    (tester) async {
      _asked.clear();
      useTestViewport(tester);
      final auth = newAuthGateway();

      await tester.pumpWidget(
        App(
          socialAuthGateway: auth,
          sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
          tasteLettersGateway: _Letters(),
          preferenceHistoryGateway: _History(),
          cardCountLoader: _cardCount,
          editorialArticleGateway: _Editorial(),
        ),
      );
      await tester.pump();
      auth.emit(SocialAuthSessionEvent.initialSession);
      await tester.pumpAndSettle();

      // Home's own data, how many cards the account has (기록하기 asks whether
      // a record is the first), and already the newest month of 기록 and the
      // posts of 피드, though neither tab has been opened.
      expect(
        _drain(),
        unorderedEquals(<String>[
          'card count',
          'letters',
          'latest',
          'month',
          'articles',
        ]),
      );

      await _tab(tester, '기록');
      expect(_drain(), isEmpty, reason: 'the month was already there');
    },
  );

  testWidgets('a saved note and a deleted card reload only what shows them', (
    tester,
  ) async {
    _asked.clear();
    useTestViewport(tester);
    openAppAtDebugRoute(AppRoute.home);
    await tester.pumpWidget(
      App(
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        tasteLettersGateway: _Letters(),
        preferenceHistoryGateway: _oneRecordHistory(),
        cardCountLoader: _cardCount,
        tasteCardGateway: _Cards(),
        recordNoteGateway: _Notes(),
      ),
    );
    await tester.pumpAndSettle();
    await _tab(tester, '내 정보');
    await _tab(tester, '기록');
    _drain();

    final record = find.byKey(
      const ValueKey<String>('history-record-$_resultId'),
    );
    await tester.ensureVisible(record);
    await tester.pumpAndSettle();
    await tester.tap(record);
    await tester.pumpAndSettle();
    final steps = <String, List<String>>{'open the card': _drain()};

    await _openOverall(tester);
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

    // The calendar shows notes; it asks again when 기록 shows next.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    steps['back to 기록 after the note'] = _drain();

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
    // Home stays built behind 기록: it asked again for what the deleted
    // card fed as the card went, and has it when it shows next.
    await _tab(tester, '홈');
    steps['to 홈 after the delete'] = _drain();

    expect(steps, <String, List<String>>{
      'open the card': ['card', 'note'],
      'open the note': [],
      'save the note': ['save note'],
      'back to 기록 after the note': ['month'],
      // The home itself reads the letters (a member without a record is
      // shown the invite), so it asks for them before 기록 asks.
      'delete the card': ['delete', 'card count', 'letters', 'latest', 'month'],
      'to 홈 after the delete': [],
    });
  });
}

/// 수정 turns the card to its 테이스팅 노트, where the 총평 line opens its
/// sheet; a card with no note opens the sheet at once.
Future<void> _openOverall(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('taste-card-more')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('taste-card-menu-edit')));
  await tester.pumpAndSettle();
  final overall = find.byKey(
    const ValueKey<String>('taste-card-note-memo-overall'),
  );
  // A card with no note opens its 총평 at once.
  if (overall.evaluate().isEmpty) return;
  await tester.ensureVisible(overall);
  await tester.pumpAndSettle();
  await tester.tap(overall);
}
