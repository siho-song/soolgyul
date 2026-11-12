import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/onboarding/presentation/onboarding_entry_screens.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_actions.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_layout.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/widgets/app_brand_logo.dart';
import 'package:soolgyul/src/widgets/app_top_bar.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';
import '../support/test_catalog.dart';

/// Picks the fixture dry white wine from the local catalog list.
Future<void> enterFirstDrink(WidgetTester tester) async {
  await startOnboarding(tester);
  await tester.enterText(find.byType(TextFormField), '테스트 드라이');
  await pumpCatalogSearch(tester);
  await tester.tap(find.text('테스트 드라이 화이트 와인'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('다음'));
  await tester.tap(find.text('다음'));
  await tester.pumpAndSettle();
}

Future<void> answerRevisit(WidgetTester tester, String answerKey) async {
  await tapSensoryOption(tester, answerKey);
  // The header's SKIP (revisit:unsure) moves on by itself.
  if (answerKey != 'revisit:unsure') {
    await tapSensoryOption(tester, 'sensory-next');
  }
}

void main() {
  testWidgets('welcome remains usable with large system text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpAppAtRoute(
      tester,
      AppRoute.onboardingWelcome,
      const Size(411, 891),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('onboarding-welcome-start')),
      findsOneWidget,
    );

    await startOnboarding(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('최근에 마신 술이 있나요?'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('the welcome slides move on by themselves and come round again', (
    tester,
  ) async {
    await tester.pumpWidget(const App(isWeb: true));
    expect(find.bySemanticsLabel('1 / 4'), findsOneWidget);

    for (final shown in <String>['2 / 4', '3 / 4', '4 / 4', '1 / 4']) {
      await tester.pump(OnboardingWelcomeScreen.slideInterval);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(shown), findsOneWidget);
    }
  });

  testWidgets('a touch on the welcome slides starts the wait again', (
    tester,
  ) async {
    await tester.pumpWidget(const App(isWeb: true));
    const almost = Duration(seconds: 3);

    await tester.pump(almost);
    final touch = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('onboarding-welcome-slides')),
      ),
    );
    await touch.up();
    await tester.pump(almost);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('1 / 4'), findsOneWidget);

    await tester.pump(OnboardingWelcomeScreen.slideInterval - almost);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 / 4'), findsOneWidget);
  });

  testWidgets('with reduced motion the welcome slide changes without sliding', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(const App(isWeb: true));

    await tester.pump(OnboardingWelcomeScreen.slideInterval);
    await tester.pump();
    expect(find.bySemanticsLabel('2 / 4'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the web starts with the unified onboarding welcome screen', (
    tester,
  ) async {
    await tester.pumpWidget(const App(isWeb: true));

    expect(find.byType(AppBrandLogo), findsOneWidget);
    const heroTitle = '내 취향 분석부터 다음 술 가이드까지';
    expect(find.text('마신 술 한 잔만 기록하면'), findsOneWidget);
    expect(find.text(heroTitle), findsOneWidget);
    expect(
      tester.getCenter(find.byType(AppBrandLogo)).dx,
      tester.getCenter(find.byType(AppTopBar)).dx,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'onboarding-welcome-image:'
          'assets/images/onboarding/onboarding_preview_card.webp',
        ),
      ),
      findsOneWidget,
    );

    // A swipe shows the next slide; the start button stays.
    await tester.fling(
      find.byKey(const ValueKey<String>('onboarding-welcome-slides')),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('라벨만 찍어도 내 입맛인지 바로 확인'), findsOneWidget);
    expect(find.text(heroTitle), findsNothing);
    expect(find.bySemanticsLabel('2 / 4'), findsOneWidget);
    expect(find.text('최근에 마신 술이 있나요?'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('onboarding-welcome-start')),
      findsOneWidget,
    );
    expect(find.text('내 취향 찾기'), findsNothing);
    expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsNothing);

    await startOnboarding(tester);
    expect(find.text('라벨만 찍어도 내 입맛인지 바로 확인'), findsNothing);
    expect(find.text('최근에 마신 술이 있나요?'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '스모키');
    await pumpCatalogSearch(tester);
    expect(find.textContaining('19세 이상'), findsNothing);
    expect(find.text('그 한 잔, 또 마시고 싶나요?'), findsNothing);
  });

  testWidgets('a signed-in session on home stays on home', (tester) async {
    final homeGateway = FakeSocialAuthGateway();
    addTearDown(homeGateway.close);
    await pumpAppAtRoute(
      tester,
      AppRoute.home,
      defaultAppTestViewport,
      homeGateway,
    );

    homeGateway.emit(SocialAuthSessionEvent.signedIn);
    await tester.pumpAndSettle();

    expect(find.text('고민 중인 술이 있나요?'), findsOneWidget);
    expect(find.text('술결에서 어떻게 불러드릴까요?'), findsNothing);
  });

  testWidgets('starts with the drink and asks the revisit judgment about it', (
    tester,
  ) async {
    await tester.pumpWidget(
      App(
        isWeb: true,
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        catalogSearchGateway: const TestCatalogGateway(),
        tasteCardGateway: _FakeTasteCardGateway(),
      ),
    );

    await startOnboarding(tester);
    expect(find.text('최근에 마신 술이 있나요?'), findsOneWidget);
    expect(find.text('건너뛸게요'), findsNothing);

    await tester.enterText(find.byType(TextFormField), '스모키');
    await pumpCatalogSearch(tester);
    final firstDrinkResult = find.ancestor(
      of: find.text('테스트 스모키 위스키'),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(firstDrinkResult);
    await tester.tapAt(
      tester.getTopLeft(firstDrinkResult) + const Offset(24, 12),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);

    await answerRevisit(tester, 'revisit:wantAgain');
    await completeUnknownSensoryQuestions(tester);
    // No photo or note page: the card follows the last question.
    expect(find.byType(TasteCardScreen), findsOneWidget);
  });

  testWidgets('smoky aroma and warmth feedback reach the server card', (
    tester,
  ) async {
    final tasteGateway = _FakeTasteCardGateway();
    await tester.pumpWidget(
      App(
        isWeb: true,
        tasteCardGateway: tasteGateway,
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        catalogSearchGateway: const TestCatalogGateway(),
      ),
    );

    await startOnboarding(tester);
    await tester.enterText(find.byType(TextFormField), '스모키');
    await pumpCatalogSearch(tester);
    await tester.tap(find.text('테스트 스모키 위스키'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    await answerRevisit(tester, 'revisit:wantAgain');
    expect(find.text('기억에 남거나 아쉬웠던 향이 있나요?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reaction:mouthfeel:bubbles:liked')),
      findsNothing,
    );
    await tapSensoryOption(tester, 'notice:aroma:smoke'); // one tap: liked
    await tapSensoryOption(tester, 'sensory-next');
    await tapSensoryOption(tester, 'reaction:taste:sweetness:fine');
    await tapSensoryOption(tester, 'reaction:taste:bitterness:fine');
    await tapSensoryOption(tester, 'sensory-next');
    await tapSensoryOption(tester, 'reaction:mouthfeel:warmth:disliked');
    await tapSensoryOption(tester, 'sensory-next');
    await tapSensoryOption(tester, 'finish:unsure');

    expect(tasteGateway.createRequests, hasLength(1));
    expect(
      tasteGateway.createRequests.single.answers.expand(
        (answer) => answer.selectedOptionKeys,
      ),
      containsAll([
        'reaction:aroma:smoke:liked',
        'reaction:mouthfeel:warmth:disliked',
      ]),
    );
    expect(
      tester
          .widget<TasteCardScreen>(find.byType(TasteCardScreen))
          .viewData
          .snapshotRef,
      tasteGateway.anonymousResult.snapshotRef,
    );

    final cardToggle = find.byKey(const ValueKey<String>('taste-card-toggle'));
    // The 한입 card is tall enough to push the bridge below the first viewport.
    await tester.scrollUntilVisible(
      cardToggle,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(cardToggle);
    await tester.pumpAndSettle();
    // The reasons start folded; the bridge opens them.
    expect(find.text('펼치기'), findsOneWidget);
    await tester.tap(cardToggle);
    await tester.pumpAndSettle();
    expect(find.text('접기'), findsOneWidget);
    // Folding scrolls back to the top, where the bridge sits below the fold.
    await tester.tap(cardToggle);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      cardToggle,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(cardToggle);
    await tester.pumpAndSettle();
    expect(find.text('펼치기'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpAppAtRoute(tester, AppRoute.profileSetup);
    final drinkInterestTiles = tester.widgetList<OnboardingDrinkTile>(
      find.byType(OnboardingDrinkTile),
    );
    expect(drinkInterestTiles, isNotEmpty);
    expect(drinkInterestTiles.every((tile) => !tile.selected), isTrue);
  });

  testWidgets('the web ends the first record with a bar fixed under the card '
      'that opens the app; nothing is saved', (tester) async {
    final tasteGateway = _FakeTasteCardGateway();
    await tester.pumpWidget(
      App(
        isWeb: true,
        tasteCardGateway: tasteGateway,
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
        catalogSearchGateway: const TestCatalogGateway(),
      ),
    );

    await enterFirstDrink(tester);
    await answerRevisit(tester, 'revisit:unsure');
    await completeUnknownSensoryQuestions(tester);

    expect(tasteGateway.createRequests, hasLength(1));
    expect(tasteGateway.createRequests.single.anonymousSessionId, isNotNull);
    final screen = tester.widget<TasteCardScreen>(find.byType(TasteCardScreen));
    expect(
      screen.viewData.snapshotRef,
      tasteGateway.anonymousResult.snapshotRef,
    );
    expect(
      find.byKey(const ValueKey<String>('save-preference-button')),
      findsNothing,
    );
    expect(find.text('Google로 계속하기'), findsNothing);

    // The bar is on screen before any scrolling and stays after it.
    final openApp = find.byKey(const ValueKey<String>('open-app-button'));
    expect(openApp, findsOneWidget);
    expect(find.text('술결 앱에서 확인하기'), findsOneWidget);
    final viewportHeight = tester.view.physicalSize.height;
    expect(tester.getBottomLeft(openApp).dy, lessThanOrEqualTo(viewportHeight));
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(openApp, findsOneWidget);
    expect(tester.getBottomLeft(openApp).dy, lessThanOrEqualTo(viewportHeight));
    expect(tasteGateway.conversionRequests, isEmpty);
  });

  group('onboarding step scaffold', () {
    testWidgets('a long page of options keeps 다음 on screen without scrolling', (
      tester,
    ) async {
      await pumpTestScreen(
        tester,
        OnboardingStepScaffold(
          title: '기억에 남거나 아쉬웠던 향이 있나요?',
          description: '한 번 터치 좋아요',
          childrenBuilder: (context, layout) => <Widget>[
            for (var i = 0; i < 30; i++)
              SizedBox(height: 56, child: Text('선택지 $i')),
          ],
          primaryAction: OnboardingStepAction(label: '다음', onPressed: () {}),
        ),
        viewport: const Size(390, 844),
      );

      final next = tester.getRect(find.text('다음'));
      expect(next.bottom, lessThanOrEqualTo(844));
      expect(find.text('선택지 29').hitTestable(), findsNothing);
    });
  });
}

final class _FakeTasteCardGateway implements TasteCardGateway {
  @override
  Future<void> deleteOwnedResult(String resultId) => throw UnimplementedError();

  bool authenticated = false;
  final List<CreateTasteCardResultRequest> createRequests =
      <CreateTasteCardResultRequest>[];
  final List<AnonymousTasteCardConversionRequest> conversionRequests =
      <AnonymousTasteCardConversionRequest>[];
  final List<String> detailRequests = <String>[];

  late final TasteCardResult anonymousResult = TasteCardResult(
    resultId: '20000000-0000-4000-8000-000000000001',
    snapshotRef: designTasteCard.snapshotRef,
    ownership: TasteCardOwnership.anonymous,
    viewData: designTasteCard,
    pendingConversion: TasteCardPendingConversion(
      anonymousSessionId: 'anonymous-session-one',
      resultId: '20000000-0000-4000-8000-000000000001',
      snapshotRef: designTasteCard.snapshotRef,
      conversionToken: 'opaque-token',
    ),
  );

  @override
  bool get isAuthenticated => authenticated;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequest request,
  ) async {
    createRequests.add(request);
    return TasteCardFinalOutcome(anonymousResult);
  }

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequest request,
  ) async {
    conversionRequests.add(request);
    return TasteCardResult(
      resultId: anonymousResult.resultId,
      snapshotRef: anonymousResult.snapshotRef,
      ownership: TasteCardOwnership.saved,
      viewData: anonymousResult.viewData,
    );
  }

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) async {
    detailRequests.add(resultId);
    return TasteCardResult(
      resultId: resultId,
      snapshotRef: anonymousResult.snapshotRef,
      ownership: TasteCardOwnership.saved,
      viewData: anonymousResult.viewData,
    );
  }
}
