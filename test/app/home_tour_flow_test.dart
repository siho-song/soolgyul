import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/home_tour/data/home_tour_memory.dart';
import 'package:soolgyul/src/features/home_tour/presentation/home_tour_overlay.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';

const _readyAccount = AccountCompletionStatus(
  profileComplete: true,
  displayName: '민지',
  adultAgeConfirmed: true,
  termsVersion: AccountPolicyVersions.terms,
  privacyVersion: AccountPolicyVersions.privacy,
  marketingOptIn: false,
  deletionState: 'active',
);

const _emptyLetters = '첫 술결을 남기면 내 취향 조각이 채워져요.';

class _Memory implements HomeTourMemory {
  _Memory({this.wasOffered = false});

  bool wasOffered;

  @override
  Future<bool> offered() async => wasOffered;

  @override
  Future<void> rememberOffered() async => wasOffered = true;
}

AppRoute _currentRoute(WidgetTester tester) =>
    AppRouterScope.of(tester.element(find.byType(AppFlow))).currentRoute;

Finder _bubble(HomeTourStep step) =>
    find.byKey(ValueKey<String>('home-tour-bubble-${step.name}'));

const _next = ValueKey<String>('home-tour-next');
const _close = ValueKey<String>('home-tour-close');

/// Opens the app on the home of a signed-in member with [cards] cards.
Future<void> _openHome(
  WidgetTester tester, {
  required HomeTourMemory? memory,
  int? cards = 0,
}) async {
  tester.view.physicalSize = defaultAppTestViewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final gateway = FakeSocialAuthGateway();
  addTearDown(gateway.close);
  await tester.pumpWidget(
    App(
      socialAuthGateway: gateway,
      accountCompletionGateway: FakeAccountCompletionGateway(
        status: _readyAccount,
      ),
      profileSummaryLoader: () async => cards == null
          ? throw StateError('offline')
          : ProfileSummary(
              cardCount: cards,
              savedArticleCount: 0,
              likedCardCount: 0,
            ),
      homeTourMemory: memory,
    ),
  );
  await tester.pump();
  gateway.emit(SocialAuthSessionEvent.initialSession);
  await tester.pumpAndSettle();
  expect(_currentRoute(tester), AppRoute.home);
}

void main() {
  testWidgets('a member without a card is walked from the 기록 button, past '
      'an example card and an example home, to the first record', (
    tester,
  ) async {
    final memory = _Memory();
    await _openHome(tester, memory: memory);

    expect(_bubble(HomeTourStep.record), findsOneWidget);
    expect(memory.wasOffered, isTrue);
    // Under the tour the home is filled with the example.
    expect(find.text(_emptyLetters), findsNothing);

    await tester.tap(find.byKey(_next));
    await tester.pumpAndSettle();
    expect(_bubble(HomeTourStep.card), findsOneWidget);
    expect(find.text('조니워커 블랙 라벨'), findsOneWidget);
    expect(find.text('예시'), findsOneWidget);

    for (final step in <HomeTourStep>[
      HomeTourStep.tasteFit,
      HomeTourStep.letters,
      HomeTourStep.guides,
      HomeTourStep.start,
    ]) {
      await tester.tap(find.byKey(_next));
      await tester.pumpAndSettle();
      expect(_bubble(step), findsOneWidget);
    }
    expect(find.text('6 / 6'), findsOneWidget);

    await tester.tap(find.text('첫 술결 남기기'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeTourOverlay), findsNothing);
    expect(_currentRoute(tester), AppRoute.onboardingSearch);
  });

  testWidgets('the guide, too tall to light whole, is lit down to just above '
      'its 추천 도수 box and the bubble sits under that', (tester) async {
    await _openHome(tester, memory: _Memory());
    for (var i = 0; i < HomeTourStep.guides.index; i++) {
      await tester.tap(find.byKey(_next));
      await tester.pumpAndSettle();
    }
    expect(_bubble(HomeTourStep.guides), findsOneWidget);

    final levels = find.text('추천 도수');
    expect(levels, findsOneWidget);
    final box = find.ancestor(of: levels, matching: find.byType(Container));
    final levelsTop = tester.getTopLeft(box.first).dy;
    final bubbleTop = tester.getTopLeft(_bubble(HomeTourStep.guides)).dy;
    // Light ends 6 above the box, the bubble's pointer hangs 14 under it.
    expect(bubbleTop, greaterThan(levelsTop));
    expect(bubbleTop, lessThan(levelsTop + 30));
  });

  testWidgets('건너뛰기 closes the tour and the home shows the member\'s own', (
    tester,
  ) async {
    await _openHome(tester, memory: _Memory());

    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();

    expect(find.byType(HomeTourOverlay), findsNothing);
    expect(_currentRoute(tester), AppRoute.home);
    expect(find.text(_emptyLetters), findsOneWidget);
  });

  testWidgets('nothing under the tour can be pressed', (tester) async {
    await _openHome(tester, memory: _Memory());

    await tester.tapAt(tester.getCenter(find.text('고민 중인 술이 있나요?')));
    await tester.pumpAndSettle();

    expect(_currentRoute(tester), AppRoute.home);
    expect(_bubble(HomeTourStep.record), findsOneWidget);
  });

  testWidgets('a member who was offered the tour is not shown it again', (
    tester,
  ) async {
    await _openHome(tester, memory: _Memory(wasOffered: true));

    expect(find.byType(HomeTourOverlay), findsNothing);
  });

  testWidgets('a member with a card is never shown the tour', (tester) async {
    final memory = _Memory();
    await _openHome(tester, memory: memory, cards: 1);

    expect(find.byType(HomeTourOverlay), findsNothing);
    expect(memory.wasOffered, isTrue);
  });

  testWidgets('while the card count is not known the tour waits for the next '
      'time the home opens', (tester) async {
    final memory = _Memory();
    await _openHome(tester, memory: memory, cards: null);

    expect(find.byType(HomeTourOverlay), findsNothing);
    expect(memory.wasOffered, isFalse);
  });

  testWidgets('without a memory nobody is shown the tour', (tester) async {
    await _openHome(tester, memory: null);

    expect(find.byType(HomeTourOverlay), findsNothing);
  });

  test('a bubble\'s words are kept whole', () {
    expect(wordsKept('맞을지 알려요\n순서'), '맞⁠을⁠지 알⁠려⁠요\n순⁠서');
  });

  group('the phone remembers the offer per account', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('one account\'s offer is not another\'s', () async {
      String? account = 'a';
      final memory = DeviceHomeTourMemory(accountId: () => account);

      expect(await memory.offered(), isFalse);
      await memory.rememberOffered();
      expect(await memory.offered(), isTrue);

      account = 'b';
      expect(await memory.offered(), isFalse);
    });

    test('nobody signed in reads as offered', () async {
      final memory = DeviceHomeTourMemory(accountId: () => null);

      expect(await memory.offered(), isTrue);
    });
  });
}
