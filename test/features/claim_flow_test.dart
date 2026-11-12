import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
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
  expect(screen.viewData, designTasteCard);
}

Future<void> _scrollToSaveButton(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey<String>('save-preference-button')),
    420,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  expect(find.text('홈으로'), findsOneWidget);
}

void main() {
  testWidgets(
    'a claim link opened while signed in is claimed at once and shows the card as saved',
    (tester) async {
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
      await tester.tap(find.text('홈으로'));
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.home);
    },
  );

  testWidgets(
    'a fresh install with the ticket in the Play referrer claims it right '
    'after the sign-in and lands on the card over home',
    (tester) async {
      final referrer = TasteCardClaimLink.build(
        'https://soolgyul.com',
        _ticket,
      ).fragment;
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
      await tester.tap(find.text('홈으로'));
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
    expect(find.text('술결 카드를 완성하지 못했어요'), findsOneWidget);
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

    final ticket = TasteCardClaimLink.build('https://soolgyul.com', _ticket);
    for (final link in <Uri>[
      // The app's own scheme is not a claim.
      Uri.parse('soolgyul://x/claim#${ticket.fragment}'),
      Uri.parse('https://soolgyul.com/faq/'),
    ]) {
      links.add(link);
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.home, reason: '$link');
      expect(tasteCard.conversionRequests, isEmpty, reason: '$link');
    }
  });

  group('claim link', () {
    const site = 'https://soolgyul.com';
    const ticket = TasteCardPendingConversion(
      anonymousSessionId: 'anon-session',
      resultId: '20000000-0000-4000-8000-000000000001',
      snapshotRef: 'snapshot/ref v3',
      conversionToken: 'a.b-c_d',
    );

    test('the link carries the whole ticket and parses back to it', () {
      final link = TasteCardClaimLink.build(site, ticket);
      expect(link.host, 'soolgyul.com');
      expect(link.path, '/claim');
      // Nothing of the ticket is in the part a server sees.
      expect(link.query, isEmpty);
      final parsed = TasteCardClaimLink.parse(link, baseUrl: site)!;
      expect(parsed.anonymousSessionId, ticket.anonymousSessionId);
      expect(parsed.resultId, ticket.resultId);
      expect(parsed.snapshotRef, ticket.snapshotRef);
      expect(parsed.conversionToken, ticket.conversionToken);
    });

    test('other links and incomplete tickets are not a claim', () {
      TasteCardPendingConversion? parse(String link) =>
          TasteCardClaimLink.parse(Uri.parse(link), baseUrl: site);
      expect(parse('https://soolgyul.com/'), isNull);
      expect(parse('https://soolgyul.com/claim#s=x&r=y'), isNull);
      expect(TasteCardClaimLink.parseInstallReferrer(null), isNull);
      expect(
        TasteCardClaimLink.parseInstallReferrer('utm_source=play'),
        isNull,
      );
    });

    test('a link is a claim only on the intro site', () {
      final ticketPart = TasteCardClaimLink.build(site, ticket).fragment;
      TasteCardPendingConversion? parse(String link) =>
          TasteCardClaimLink.parse(Uri.parse(link), baseUrl: site);
      // The site answers on www and with a trailing slash.
      expect(parse('https://www.soolgyul.com/claim/#$ticketPart'), isNotNull);
      // Any page can write a link with the app's scheme or another host.
      expect(parse('soolgyul://x/claim#$ticketPart'), isNull);
      expect(parse('https://evil.example/claim#$ticketPart'), isNull);
      expect(parse('http://soolgyul.com/claim#$ticketPart'), isNull);
      // The ticket is read after the "#" only.
      expect(parse('https://soolgyul.com/claim?$ticketPart'), isNull);
    });

    test('the Play install referrer is the link\'s part after the #', () {
      final query = TasteCardClaimLink.build(site, ticket).fragment;
      final parsed = TasteCardClaimLink.parseInstallReferrer(query)!;
      expect(parsed.resultId, ticket.resultId);
      expect(parsed.snapshotRef, ticket.snapshotRef);
      expect(parsed.conversionToken, ticket.conversionToken);
    });
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
