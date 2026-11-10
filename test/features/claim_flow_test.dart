import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_gateway.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_link.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/claim_link.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';

// A card made on the web follows the visitor into the app: its ticket
// arrives as a link or as the Play install referrer and is claimed for the
// account, before or after the sign-in.

const _ticket = TasteCardPendingConversion(
  anonymousSessionId: 'anonymous-session-web',
  resultId: '20000000-0000-4000-8000-000000000001',
  snapshotRef: 'snapshot-web',
  conversionToken: 'opaque-token',
);

const _readyAccount = AccountCompletionStatus(
  profileComplete: true,
  displayName: '민지',
  adultAgeConfirmed: true,
  termsVersion: AccountPolicyVersions.terms,
  privacyVersion: AccountPolicyVersions.privacy,
  marketingOptIn: false,
  deletionState: 'active',
);

AppRoute _currentRoute(WidgetTester tester) =>
    AppRouterScope.of(tester.element(find.byType(AppFlow))).currentRoute;

Future<(FakeSocialAuthGateway, _ClaimingTasteCardGateway)> _pumpApp(
  WidgetTester tester, {
  Stream<Uri>? links,
  String? installReferrer,
  EditorialArticleGateway? editorial,
}) async {
  tester.view.physicalSize = defaultAppTestViewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final social = FakeSocialAuthGateway();
  addTearDown(social.close);
  final tasteCard = _ClaimingTasteCardGateway();
  await tester.pumpWidget(
    App(
      socialAuthGateway: social,
      accountCompletionGateway: FakeAccountCompletionGateway(
        status: _readyAccount,
      ),
      tasteCardGateway: tasteCard,
      editorialArticleGateway: editorial,
      incomingLinks: links,
      installReferrer: installReferrer == null
          ? null
          : () async => installReferrer,
      sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
    ),
  );
  await tester.pump();
  return (social, tasteCard);
}

void _expectSavedCard(WidgetTester tester, _ClaimingTasteCardGateway gateway) {
  expect(_currentRoute(tester), AppRoute.onboardingResult);
  expect(gateway.conversionRequests, hasLength(1));
  expect(gateway.conversionRequests.single.resultId, _ticket.resultId);
  expect(gateway.conversionRequests.single.conversionToken, 'opaque-token');
  final screen = tester.widget<TasteCardScreen>(find.byType(TasteCardScreen));
  expect(screen.isSaved, isTrue);
  expect(screen.viewData, designTasteCard);
}

Future<void> _scrollToSaveButton(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey<String>('save-preference-button')),
    420,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  expect(find.text('저장 완료'), findsOneWidget);
}

class _Editorial implements EditorialArticleGateway {
  @override
  Future<List<EditorialArticle>> fetchPublishedArticles() async =>
      <EditorialArticle>[
        EditorialArticle(
          id: 'post-1',
          body: '가을 막걸리',
          publishedAt: DateTime.utc(2026, 11, 10),
          mediaAssets: const [],
          interestKeys: const [],
        ),
      ];

  @override
  Future<List<EditorialArticle>> fetchSavedArticles() async => const [];

  @override
  Future<void> saveArticle(String articleId) async {}

  @override
  Future<void> unsaveArticle(String articleId) async {}
}

void main() {
  testWidgets('a shared post link opened while signed in opens that post', (
    tester,
  ) async {
    final links = StreamController<Uri>.broadcast();
    addTearDown(links.close);
    final (social, tasteCard) = await _pumpApp(
      tester,
      links: links.stream,
      editorial: _Editorial(),
    );
    tasteCard.authenticated = true;
    social.emit(SocialAuthSessionEvent.initialSession);
    await tester.pumpAndSettle();
    expect(_currentRoute(tester), AppRoute.home);

    links.add(EditorialArticleLink.build('https://soolgyul.com', 'post-1'));
    await tester.pumpAndSettle();
    expect(_currentRoute(tester), AppRoute.editorialArticle);
    expect(find.textContaining('가을 막걸리'), findsWidgets);

    // A post that is gone says so and stays where it was.
    AppRouterScope.of(tester.element(find.byType(AppFlow))).pop();
    await tester.pumpAndSettle();
    links.add(Uri.parse('https://soolgyul.com/article/?id=gone'));
    await tester.pumpAndSettle();
    expect(_currentRoute(tester), AppRoute.home);
    expect(find.text('글을 찾을 수 없어요.'), findsOneWidget);
  });

  testWidgets('a fresh install from a shared post link opens the post right '
      'after the sign-in', (tester) async {
    final (social, tasteCard) = await _pumpApp(
      tester,
      installReferrer: 'article=post-1',
      editorial: _Editorial(),
    );
    social.emit(SocialAuthSessionEvent.noSession);
    await tester.pumpAndSettle();
    expect(_currentRoute(tester), AppRoute.appLogin);

    tasteCard.authenticated = true;
    social.emit(SocialAuthSessionEvent.signedIn);
    await tester.pumpAndSettle();
    expect(_currentRoute(tester), AppRoute.editorialArticle);
  });

  testWidgets('a shared post link opened before the sign-in opens the post '
      'once the account lands on home', (tester) async {
    final links = StreamController<Uri>.broadcast();
    addTearDown(links.close);
    final (social, tasteCard) = await _pumpApp(
      tester,
      links: links.stream,
      editorial: _Editorial(),
    );
    links.add(EditorialArticleLink.build('https://soolgyul.com', 'post-1'));
    await tester.pump();
    tasteCard.authenticated = true;
    social.emit(SocialAuthSessionEvent.initialSession);
    await tester.pumpAndSettle();
    expect(_currentRoute(tester), AppRoute.editorialArticle);
  });

  testWidgets('a claim link opened while signed in shows the card as saved', (
    tester,
  ) async {
    final links = StreamController<Uri>.broadcast();
    addTearDown(links.close);
    final (social, tasteCard) = await _pumpApp(tester, links: links.stream);
    tasteCard.authenticated = true;
    social.emit(SocialAuthSessionEvent.initialSession);
    await tester.pumpAndSettle();
    expect(_currentRoute(tester), AppRoute.home);

    links.add(TasteCardClaimLink.build('https://soolgyul.com', _ticket));
    await tester.pumpAndSettle();

    _expectSavedCard(tester, tasteCard);
    // Back from the card is home, not the web's onboarding.
    await _scrollToSaveButton(tester);
    await tester.tap(find.text('저장 완료'));
    await tester.pumpAndSettle();
    expect(_currentRoute(tester), AppRoute.home);
  });

  testWidgets(
    'a fresh install with the ticket in the Play referrer claims it right '
    'after the sign-in and lands on the card over home',
    (tester) async {
      final referrer = TasteCardClaimLink.build(
        'https://soolgyul.com',
        _ticket,
      ).query;
      final (social, tasteCard) = await _pumpApp(
        tester,
        installReferrer: referrer,
      );
      social.emit(SocialAuthSessionEvent.noSession);
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.appLogin);
      expect(tasteCard.conversionRequests, isEmpty);

      tasteCard.authenticated = true;
      await tester.tap(
        find.byKey(const ValueKey<String>('kakao-login-button')),
      );
      await tester.pumpAndSettle();

      _expectSavedCard(tester, tasteCard);
      await _scrollToSaveButton(tester);
      await tester.tap(find.text('저장 완료'));
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.home);
    },
  );

  testWidgets('a claim the server refuses shows the retry, not a card', (
    tester,
  ) async {
    final links = StreamController<Uri>.broadcast();
    addTearDown(links.close);
    final (social, tasteCard) = await _pumpApp(tester, links: links.stream);
    tasteCard
      ..authenticated = true
      ..refuseConversion = true;
    social.emit(SocialAuthSessionEvent.initialSession);
    await tester.pumpAndSettle();

    links.add(TasteCardClaimLink.build('https://soolgyul.com', _ticket));
    await tester.pumpAndSettle();

    expect(_currentRoute(tester), AppRoute.onboardingResult);
    expect(find.byType(TasteCardScreen), findsNothing);
    expect(find.text('술결을 완성하지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    tasteCard.refuseConversion = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(tasteCard.conversionRequests, hasLength(2));
    expect(find.byType(TasteCardScreen), findsOneWidget);
  });

  testWidgets('a link that is not a claim changes nothing', (tester) async {
    final links = StreamController<Uri>.broadcast();
    addTearDown(links.close);
    final (social, tasteCard) = await _pumpApp(tester, links: links.stream);
    tasteCard.authenticated = true;
    social.emit(SocialAuthSessionEvent.initialSession);
    await tester.pumpAndSettle();

    links.add(Uri.parse('https://soolgyul.com/faq/'));
    await tester.pumpAndSettle();

    expect(_currentRoute(tester), AppRoute.home);
    expect(tasteCard.conversionRequests, isEmpty);
  });
}

final class _ClaimingTasteCardGateway implements TasteCardGateway {
  bool authenticated = false;
  bool refuseConversion = false;
  final List<AnonymousTasteCardConversionRequest> conversionRequests =
      <AnonymousTasteCardConversionRequest>[];

  @override
  bool get isAuthenticated => authenticated;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequest request,
  ) async => throw UnimplementedError('the claim flow creates no card');

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequest request,
  ) async {
    conversionRequests.add(request);
    if (refuseConversion) {
      throw const TasteCardGatewayException(
        TasteCardGatewayOperation.convert,
        code: 'conversion_token_expired',
      );
    }
    return TasteCardResult(
      resultId: request.resultId,
      recordId: '30000000-0000-4000-8000-000000000001',
      snapshotRef: _ticket.snapshotRef,
      ownership: TasteCardOwnership.saved,
      viewData: designTasteCard,
    );
  }

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) async =>
      throw UnimplementedError('the claim flow opens no saved card');

  @override
  Future<void> deleteOwnedResult(String resultId) async =>
      throw UnimplementedError('the claim flow deletes no card');
}
