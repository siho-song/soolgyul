import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/features/home/data/next_drink_guides.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/profile/data/liked_cards_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import '../support/app_test_harness.dart';

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
  Future<void> like(String cardId) async {}
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

    // Home and 취향 ask again on every visit; My Page's counts are asked
    // once and kept; saved cards are asked each time they open.
    expect(steps, <String, List<String>>{
      'open home': ['letters', 'guides'],
      'to 취향': ['latest', 'month'],
      'to 마이': ['summary'],
      'open saved cards': ['liked'],
      'back to 마이': [],
      'back to 홈': ['letters', 'guides'],
      'back to 취향': ['latest', 'month'],
      'back to 마이 again': [],
    });
  });
}
