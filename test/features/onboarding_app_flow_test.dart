import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_actions.dart';
import 'package:soolgyul/src/features/onboarding/presentation/onboarding_result_screen.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/widgets/app_brand_logo.dart';
import 'package:soolgyul/src/widgets/app_top_bar.dart';

import '../support/app_test_harness.dart';

/// Picks the fixture dry white wine from the local catalog list.
Future<void> enterFirstDrink(WidgetTester tester) async {
  await startOnboarding(tester);
  await tester.enterText(find.byType(TextFormField), '테스트 드라이');
  await tester.pump();
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
    expect(find.text('최근에 마신 술은 무엇인가요?'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('the web starts with the unified onboarding welcome screen', (
    tester,
  ) async {
    await tester.pumpWidget(const App(isWeb: true));

    expect(find.byType(AppBrandLogo), findsOneWidget);
    const heroTitle = '나에게 맞는 술을 몰라\n고르기 힘든 적 있으셨죠?';
    const heroDescription = '딱 1분, 내 취향 발견과 실패없는 다음 술 가이드까지';
    expect(find.text(heroTitle), findsOneWidget);
    expect(find.text(heroDescription), findsOneWidget);
    expect(
      tester.getCenter(find.byType(AppBrandLogo)).dx,
      tester.getCenter(find.byType(AppTopBar)).dx,
    );
    final heroImage = find.byKey(
      const ValueKey<String>('onboarding-welcome-image'),
    );
    expect(
      tester.getTopLeft(heroImage).dx,
      greaterThan(tester.getTopLeft(find.text(heroTitle)).dx),
    );
    expect(
      find.byKey(const ValueKey<String>('onboarding-welcome-image-fade')),
      findsOneWidget,
    );
    expect(find.text('최근에 마신 술은 무엇인가요?'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('onboarding-welcome-start')),
      findsOneWidget,
    );
    expect(find.text('내 취향 찾기'), findsNothing);
    expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsNothing);

    await startOnboarding(tester);
    expect(find.text(heroTitle), findsNothing);
    expect(find.text('최근에 마신 술은 무엇인가요?'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '스모키');
    await tester.pump();
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
      const App(
        isWeb: true,
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
      ),
    );

    await startOnboarding(tester);
    expect(find.text('최근에 마신 술은 무엇인가요?'), findsOneWidget);
    expect(find.text('건너뛸게요'), findsNothing);

    await tester.enterText(find.byType(TextFormField), '스모키');
    await tester.pump();
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
    expect(find.byType(OnboardingResultScreen), findsOneWidget);
  });

  testWidgets('accepts a non-empty direct drink name but never a name skip', (
    tester,
  ) async {
    await tester.pumpWidget(
      const App(
        isWeb: true,
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
      ),
    );

    expect(find.text('건너뛸게요'), findsNothing);
    await enterFirstDrink(tester);

    expect(find.text('이 술, 다음에 또 마시고 싶나요?'), findsOneWidget);
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
      ),
    );

    await startOnboarding(tester);
    await tester.enterText(find.byType(TextFormField), '스모키');
    await tester.pump();
    await tester.tap(find.text('테스트 스모키 위스키'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    await answerRevisit(tester, 'revisit:wantAgain');
    expect(find.text('좋았거나, 거슬렸던 향이 있나요?'), findsOneWidget);
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
          .widget<OnboardingResultScreen>(find.byType(OnboardingResultScreen))
          .viewData
          ?.snapshotRef,
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
    expect(find.text('자세히 보기'), findsOneWidget);
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
    expect(find.text('자세히 보기'), findsOneWidget);

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
      ),
    );

    await enterFirstDrink(tester);
    await answerRevisit(tester, 'revisit:unsure');
    await completeUnknownSensoryQuestions(tester);

    expect(tasteGateway.createRequests, hasLength(1));
    expect(tasteGateway.createRequests.single.anonymousSessionId, isNotNull);
    final screen = tester.widget<OnboardingResultScreen>(
      find.byType(OnboardingResultScreen),
    );
    expect(
      screen.viewData?.snapshotRef,
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
    expect(find.text('앱에서 내 술결 확인하기'), findsOneWidget);
    final viewportHeight = tester.view.physicalSize.height;
    expect(tester.getBottomLeft(openApp).dy, lessThanOrEqualTo(viewportHeight));
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(openApp, findsOneWidget);
    expect(tester.getBottomLeft(openApp).dy, lessThanOrEqualTo(viewportHeight));
    expect(tasteGateway.conversionRequests, isEmpty);
  });
}

final class _FakeTasteCardGateway implements TasteCardGateway {
  @override
  Future<void> deleteOwnedResult(String resultId) => throw UnimplementedError();

  bool authenticated = false;
  final List<CreateTasteCardResultRequestV1> createRequests =
      <CreateTasteCardResultRequestV1>[];
  final List<AnonymousTasteCardConversionRequestV1> conversionRequests =
      <AnonymousTasteCardConversionRequestV1>[];
  final List<String> detailRequests = <String>[];

  late final TasteCardResult anonymousResult = TasteCardResult(
    resultId: '20000000-0000-4000-8000-000000000001',
    snapshotRef: TasteCardSnapshotViewData.designFixture.snapshotRef,
    ownership: TasteCardOwnership.anonymous,
    viewData: TasteCardSnapshotViewData.designFixture,
    pendingConversion: TasteCardPendingConversion(
      anonymousSessionId: 'anonymous-session-one',
      resultId: '20000000-0000-4000-8000-000000000001',
      snapshotRef: TasteCardSnapshotViewData.designFixture.snapshotRef,
      conversionToken: 'opaque-token',
    ),
  );

  @override
  bool get isAuthenticated => authenticated;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequestV1 request,
  ) async {
    createRequests.add(request);
    return TasteCardFinalOutcome(anonymousResult);
  }

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequestV1 request,
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
