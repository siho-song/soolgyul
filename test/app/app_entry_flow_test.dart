import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/account_deletion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/features/profile/presentation/drink_interest_sheet.dart';
import 'package:soolgyul/src/features/profile/presentation/account_deleting_sheet.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';

const _loginHeadline = '내 취향을 발견하고,\n딱 맞는 한 잔을 찾아보세요.';
const _loading = ValueKey<String>('app-loading');

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

ProfileSummaryLoader _summaryWith(int cardCount) =>
    () async => ProfileSummary(
      cardCount: cardCount,
      savedArticleCount: 0,
      likedCardCount: 0,
    );

Future<FakeSocialAuthGateway> _pumpApp(
  WidgetTester tester, {
  AccountCompletionGateway? accountCompletion,
  ProfileSummaryLoader? profileSummary,
  AccountDeletionGateway? accountDeletion,
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
      accountCompletionGateway: accountCompletion,
      profileSummaryLoader: profileSummary,
      accountDeletionGateway: accountDeletion,
    ),
  );
  await tester.pump();
  return gateway;
}

class _FakeDeletionGateway implements AccountDeletionGateway {
  _FakeDeletionGateway(this.status);

  AccountDeletionStatus status;
  int deletions = 0;
  int restores = 0;

  int fetches = 0;

  @override
  Future<AccountDeletionStatus> fetchStatus() async {
    fetches += 1;
    return status;
  }

  /// What the real gateway does once the server has scheduled it.
  Future<void> Function()? afterScheduled;

  @override
  Future<void> requestDeletion() async {
    deletions += 1;
    await afterScheduled?.call();
  }

  @override
  Future<void> restore() async {
    restores += 1;
    status = const AccountDeletionStatus(state: 'active');
  }
}

/// A sign-out the server cannot be told about.
class _FailingSignOutGateway extends FakeSocialAuthGateway {
  @override
  Future<void> signOut() async {
    signOutRequests += 1;
    throw TimeoutException('logout');
  }
}

void main() {
  group('app entry', () {
    testWidgets('the app starts on loading and opens login without a session', (
      tester,
    ) async {
      final gateway = await _pumpApp(tester);
      expect(find.byKey(_loading), findsOneWidget);
      expect(_currentRoute(tester), AppRoute.appLoading);

      gateway.emit(SocialAuthSessionEvent.noSession);
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.appLogin);
      expect(find.text(_loginHeadline), findsOneWidget);
      expect(find.byTooltip('이전 화면으로 이동'), findsNothing);
      expect(find.text('최근에 마신 술이 있나요?'), findsNothing);
    });

    testWidgets('a saved session with a saved card opens home', (tester) async {
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(status: _readyAccount),
        profileSummary: _summaryWith(1),
      );

      gateway.emit(SocialAuthSessionEvent.initialSession);
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.home);
      expect(find.text('고민 중인 술이 있나요?'), findsOneWidget);
    });

    testWidgets('an account without a card opens home, and 기록 starts the first '
        'record with a way back', (tester) async {
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(status: _readyAccount),
        profileSummary: _summaryWith(0),
      );

      gateway.emit(SocialAuthSessionEvent.initialSession);
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.home);

      await tester.tap(find.text('기록'));
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.onboardingWelcome);
      expect(
        find.byKey(const ValueKey<String>('onboarding-welcome-start')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.home);
    });

    testWidgets('기록 on an account with a card opens the record search', (
      tester,
    ) async {
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(status: _readyAccount),
        profileSummary: _summaryWith(1),
      );

      gateway.emit(SocialAuthSessionEvent.initialSession);
      await tester.pumpAndSettle();
      await tester.tap(find.text('기록'));
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.recordSearch);
    });

    testWidgets('a new account goes from profile setup to home', (
      tester,
    ) async {
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(),
        profileSummary: _summaryWith(0),
      );
      gateway.emit(SocialAuthSessionEvent.noSession);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('google-login-button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '테스터');
      await tester.pump();
      await tester.ensureVisible(find.text('와인'));
      await tester.tap(find.text('와인'));
      await tester.pump();
      await completeRequiredAccountConfirmation(tester);

      expect(_currentRoute(tester), AppRoute.home);
    });

    testWidgets('login with an unfinished account continues to profile setup', (
      tester,
    ) async {
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(),
      );
      gateway.emit(SocialAuthSessionEvent.noSession);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('kakao-login-button')),
      );
      await tester.pumpAndSettle();

      expect(gateway.requestedProviders, [SocialAuthProvider.kakao]);
      expect(_currentRoute(tester), AppRoute.profileSetup);
      expect(find.text('술결을 시작해 볼까요?'), findsOneWidget);

      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.appLogin);
    });

    testWidgets('a login that could not be finished on the way back is said; '
        'a renewal that failed offline is not', (tester) async {
      final gateway = await _pumpApp(tester);
      gateway.emit(SocialAuthSessionEvent.noSession);
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.appLogin);

      gateway.emitError(TimeoutException('renewal'));
      await tester.pump();
      expect(find.textContaining('로그인을 완료하지 못했어요'), findsNothing);

      gateway.emitError(StateError('code exchange refused'));
      await tester.pump();
      expect(find.textContaining('로그인을 완료하지 못했어요'), findsOneWidget);
      expect(_currentRoute(tester), AppRoute.appLogin);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('without an auth gateway the app opens login', (tester) async {
      tester.view.physicalSize = defaultAppTestViewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.appLogin);
      expect(find.text(_loginHeadline), findsOneWidget);
    });

    testWidgets('loading gives up on a silent session check', (tester) async {
      await _pumpApp(tester);
      expect(_currentRoute(tester), AppRoute.appLoading);

      // Past the coordinator's silent-session fallback (3 s).
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.appLogin);
    });
  });

  group('account deletion', () {
    testWidgets('deleting the account signs out and returns to login', (
      tester,
    ) async {
      final socialGateway = FakeSocialAuthGateway();
      addTearDown(socialGateway.close);
      final deletion = _FakeDeletionGateway(
        const AccountDeletionStatus(state: 'active'),
      );
      await pumpAppAtRoute(
        tester,
        AppRoute.policy,
        defaultAppTestViewport,
        socialGateway,
        null,
        null,
        null,
        null,
        null,
        deletion,
      );

      final entry = find.byKey(
        const ValueKey<String>('policy-account-deletion'),
      );
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(deletion.deletions, 0);

      await tester.tap(
        find.byKey(const ValueKey<String>('policy-account-deletion-request')),
      );
      await tester.pumpAndSettle();

      expect(deletion.deletions, 1);
      expect(socialGateway.signOutRequests, 1);
      expect(_currentRoute(tester), AppRoute.appLogin);
    });

    testWidgets('a withdrawal says it was received, never that the member was '
        'signed out, even when the sign-out that follows fails', (
      tester,
    ) async {
      final socialGateway = _FailingSignOutGateway();
      addTearDown(socialGateway.close);
      final deletion = _FakeDeletionGateway(
        const AccountDeletionStatus(state: 'active'),
      );
      // The real gateway ends this phone's session itself.
      deletion.afterScheduled = () async =>
          socialGateway.emit(SocialAuthSessionEvent.signedOut);
      await pumpAppAtRoute(
        tester,
        AppRoute.policy,
        defaultAppTestViewport,
        socialGateway,
        null,
        null,
        null,
        null,
        null,
        deletion,
      );

      final entry = find.byKey(
        const ValueKey<String>('policy-account-deletion'),
      );
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('policy-account-deletion-request')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(deletion.deletions, 1);
      expect(_currentRoute(tester), AppRoute.appLogin);
      expect(find.textContaining('탈퇴가 접수됐어요'), findsOneWidget);
      expect(find.textContaining('로그아웃됐어요'), findsNothing);
      expect(find.textContaining('처리하지 못했어요'), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets(
      'signing in within the 30 days restores the account without asking',
      (tester) async {
        final deletion = _FakeDeletionGateway(
          AccountDeletionStatus(
            state: 'scheduled',
            canRestore: true,
            deadline: DateTime(2026, 12, 1),
          ),
        );
        final completion = FakeAccountCompletionGateway(status: _readyAccount);
        final gateway = await _pumpApp(
          tester,
          accountCompletion: completion,
          profileSummary: _summaryWith(1),
          accountDeletion: deletion,
        );

        gateway.emit(SocialAuthSessionEvent.initialSession);
        await tester.pumpAndSettle();

        expect(deletion.restores, 1);
        expect(
          completion.statusRequests,
          2,
          reason:
              'asked while the deletion was checked, and again once the '
              'account was restored',
        );
        expect(find.byType(AccountDeletingSheet), findsNothing);
        expect(find.text('탈퇴가 취소되고 계정이 복구됐어요.'), findsOneWidget);
        expect(_currentRoute(tester), AppRoute.home);
      },
    );

    testWidgets(
      'a session past the 30 days is told of the deletion and signed out',
      (tester) async {
        final deletion = _FakeDeletionGateway(
          const AccountDeletionStatus(state: 'scheduled'),
        );
        final gateway = await _pumpApp(
          tester,
          accountCompletion: FakeAccountCompletionGateway(
            status: _readyAccount,
          ),
          profileSummary: _summaryWith(1),
          accountDeletion: deletion,
        );

        gateway.emit(SocialAuthSessionEvent.initialSession);
        await tester.pumpAndSettle();

        expect(find.byType(AccountDeletingSheet), findsOneWidget);
        await tester.tap(find.text('확인'));
        await tester.pumpAndSettle();
        expect(deletion.restores, 0);
        expect(_currentRoute(tester), AppRoute.appLogin);
      },
    );
  });

  group('app navigation', () {
    testWidgets('detail navigation and system back use the typed route stack', (
      tester,
    ) async {
      await pumpAppAtRoute(tester, AppRoute.profile);

      await tester.tap(
        find.byKey(const ValueKey<String>('profile-interest-settings')),
      );
      await tester.pumpAndSettle();

      // 관심 주종 opens as a sheet over My Page, not a page of its own.
      final navigation = AppRouterScope.of(
        tester.element(find.byType(AppFlow)),
      );
      expect(find.byType(DrinkInterestSheet), findsOneWidget);
      expect(navigation.currentRoute, AppRoute.profile);

      // A tap above the sheet closes it.
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      expect(find.byType(DrinkInterestSheet), findsNothing);
      expect(navigation.currentRoute, AppRoute.profile);
      expect(find.text('민지'), findsOneWidget);
    });

    testWidgets('policy logout ends the auth session and returns to login', (
      tester,
    ) async {
      final gateway = FakeSocialAuthGateway();
      await pumpAppAtRoute(
        tester,
        AppRoute.policy,
        defaultAppTestViewport,
        gateway,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('policy-sign-out')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('policy-sign-out')));
      await tester.pumpAndSettle();
      expect(find.text('로그아웃하시겠어요?'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('policy-sign-out-confirm')),
      );
      await tester.pumpAndSettle();

      expect(gateway.signOutRequests, 1);
      expect(_currentRoute(tester), AppRoute.appLogin);
    });

    testWidgets('record start opens search directly and back returns home', (
      tester,
    ) async {
      await pumpAppAtRoute(tester, AppRoute.home);

      await tester.tap(find.text('기록'));
      await tester.pumpAndSettle();
      expect(find.text('최근에 마신 술이 있나요?'), findsOneWidget);
      expect(find.byTooltip('이전 화면으로 이동'), findsOneWidget);

      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();
      expect(find.text('고민 중인 술이 있나요?'), findsOneWidget);
      expect(find.byTooltip('이전 화면으로 이동'), findsNothing);
    });
  });
}
