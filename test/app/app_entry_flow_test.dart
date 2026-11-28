import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/core/saved_views.dart';
import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/notifications/data/notification_access.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/account_deletion_gateway.dart';
import 'package:soolgyul/src/features/records/data/card_count.dart';
import 'package:soolgyul/src/features/profile/presentation/drink_interest_sheet.dart';
import 'package:soolgyul/src/features/profile/presentation/account_deleting_dialog.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';
import 'package:soolgyul/src/widgets/app_bottom_nav.dart';

import '../support/app_test_harness.dart';
import '../support/fake_account_deletion.dart';
import '../support/memory_saved_views.dart';

const _loginHeadline = '내 취향을 발견하고,\n딱 맞는 한 잔을 찾아보세요.';
const _loading = ValueKey<String>('app-loading');

AppRoute _currentRoute(WidgetTester tester) =>
    AppRouterScope.of(tester.element(find.byType(AppFlow))).currentRoute;

CardCountLoader _cardCount(int cards) =>
    () async => cards;

Future<FakeSocialAuthGateway> _pumpApp(
  WidgetTester tester, {
  AccountCompletionGateway? accountCompletion,
  CardCountLoader? cardCount,
  AccountDeletionGateway? accountDeletion,
  SavedViews? savedViews,
}) async {
  useTestViewport(tester);
  final gateway = newAuthGateway();
  await tester.pumpWidget(
    App(
      socialAuthGateway: gateway,
      accountCompletionGateway: accountCompletion,
      cardCountLoader: cardCount,
      accountDeletionGateway: accountDeletion,
      savedViews: savedViews,
    ),
  );
  await tester.pump();
  return gateway;
}

/// This phone's notifications, noting in [steps] when the server is told
/// to forget it and to know it again.
class _PhoneNotifications extends PretendNotificationAccess {
  _PhoneNotifications(this.steps);

  final List<String> steps;

  @override
  Future<void> forgetThisPhone() async => steps.add('forget');

  @override
  Future<void> resume() async => steps.add('resume');
}

/// Announces the new session before the login call returns, as the auth
/// client does.
class _AnnouncingAuthGateway extends FakeSocialAuthGateway {
  @override
  Future<SocialAuthResult> signIn(SocialAuthProvider provider) {
    emit(SocialAuthSessionEvent.signedIn);
    return super.signIn(provider);
  }
}

/// Answers the sign-up state when the test lets it.
class _SlowAccountCompletionGateway extends FakeAccountCompletionGateway {
  final answer = Completer<AccountCompletionStatus>();

  @override
  Future<AccountCompletionStatus> fetchStatus() => answer.future;
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
      expect(find.text('기록하고자 하는 술을 골라주세요.'), findsNothing);
    });

    testWidgets('a saved session with a saved card opens home', (tester) async {
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(
          status: readyAccountStatus,
        ),
        cardCount: _cardCount(1),
      );

      gateway.emit(SocialAuthSessionEvent.initialSession);
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.home);
      expect(find.text('고민 중인 술이 있나요?'), findsOneWidget);
    });

    testWidgets('an account without a card opens home, and 기록하기 starts the '
        'first record with a way back', (tester) async {
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(
          status: readyAccountStatus,
        ),
        cardCount: _cardCount(0),
      );

      gateway.emit(SocialAuthSessionEvent.initialSession);
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.home);

      await tester.tap(find.byKey(const ValueKey<String>('home-record-chip')));
      await tester.pumpAndSettle();

      // Straight to the drink search: the intro is for a visitor.
      expect(_currentRoute(tester), AppRoute.onboardingSearch);
      expect(
        find.byKey(const ValueKey<String>('onboarding-welcome-start')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.home);
    });

    testWidgets('기록하기 on an account with a card opens the record search', (
      tester,
    ) async {
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(
          status: readyAccountStatus,
        ),
        cardCount: _cardCount(1),
      );

      gateway.emit(SocialAuthSessionEvent.initialSession);
      await tester.pumpAndSettle();
      // Four tabs under home, and none of them starts a record.
      final bar = find.byType(AppBottomNav);
      expect(
        [
          for (final tab in tester.widgetList<AppBottomNavItem>(
            find.descendant(of: bar, matching: find.byType(AppBottomNavItem)),
          ))
            tab.label,
        ],
        ['홈', '기록', '피드', '내 정보'],
      );
      await tester.tap(find.descendant(of: bar, matching: find.text('기록')));
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.preference);
      await tester.tap(find.descendant(of: bar, matching: find.text('홈')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('home-record-chip')));
      await tester.pumpAndSettle();

      // The drink search opens over home, without the bar; the way back
      // and the system back lead to home.
      expect(_currentRoute(tester), AppRoute.recordSearch);
      expect(bar, findsNothing);
      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.home);

      await tester.tap(find.byKey(const ValueKey<String>('home-record-chip')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.home);
      expect(bar, findsOneWidget);
    });

    testWidgets('a new account goes from profile setup to home, and the next '
        'launch may open home at once', (tester) async {
      final phone = MemorySavedViews();
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(),
        cardCount: _cardCount(0),
        savedViews: phone,
      );
      gateway.emit(SocialAuthSessionEvent.noSession);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('google-login-button')),
      );
      await tester.pumpAndSettle();

      await completeProfileSetup(tester, name: '테스터');

      expect(_currentRoute(tester), AppRoute.home);
      expect(await phone.read('entered'), <String, Object?>{'ready': true});
      // Advertising was not agreed to, so nothing is said about it.
      expect(find.textContaining('광고성 정보 수신'), findsNothing);
    });

    testWidgets('a new account that agreed to advertising is told so, with '
        'the day, on the page it lands on', (tester) async {
      final gateway = await _pumpApp(
        tester,
        accountCompletion: FakeAccountCompletionGateway(),
        cardCount: _cardCount(0),
      );
      gateway.emit(SocialAuthSessionEvent.noSession);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('google-login-button')),
      );
      await tester.pumpAndSettle();

      await completeProfileSetup(tester, name: '테스터', advertising: true);

      expect(_currentRoute(tester), AppRoute.home);
      final today = DateTime.now();
      expect(
        find.text(
          '술결의 광고성 정보 수신 동의가 '
          '${today.year}년 ${today.month}월 ${today.day}일 처리되었어요.',
        ),
        findsOneWidget,
      );
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
      expect(find.text('닉네임을 알려 주세요'), findsOneWidget);

      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.appLogin);
    });

    testWidgets('back from profile setup, the account\'s own login button '
        'returns to it as it was left, without another login', (tester) async {
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
      // The session that login left.
      gateway.signedInProvider = SocialAuthProvider.kakao;
      await tester.enterText(find.byType(TextFormField), '테스터');
      await tester.pump();

      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.appLogin);
      await tester.tap(
        find.byKey(const ValueKey<String>('kakao-login-button')),
      );
      await tester.pumpAndSettle();

      expect(_currentRoute(tester), AppRoute.profileSetup);
      expect(gateway.requestedProviders, [SocialAuthProvider.kakao]);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
        '테스터',
      );

      // Another provider's button is another login.
      await tester.tap(find.byTooltip('이전 화면으로 이동'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('google-login-button')),
      );
      await tester.pumpAndSettle();
      expect(gateway.requestedProviders, [
        SocialAuthProvider.kakao,
        SocialAuthProvider.google,
      ]);
      expect(_currentRoute(tester), AppRoute.profileSetup);
    });

    testWidgets('after a login went through, the login buttons stay busy '
        'until the app has opened', (tester) async {
      useTestViewport(tester);
      final gateway = _AnnouncingAuthGateway();
      addTearDown(gateway.close);
      final completion = _SlowAccountCompletionGateway();
      await tester.pumpWidget(
        App(
          socialAuthGateway: gateway,
          accountCompletionGateway: completion,
          cardCountLoader: _cardCount(1),
        ),
      );
      await tester.pump();
      gateway.emit(SocialAuthSessionEvent.noSession);
      await tester.pumpAndSettle();

      final kakao = find.byKey(const ValueKey<String>('kakao-login-button'));
      await tester.tap(kakao);
      await tester.pump();
      await tester.pump();

      // The account is still being asked about: the login screen waits.
      expect(_currentRoute(tester), AppRoute.appLogin);
      expect(
        find.descendant(
          of: kakao,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('google-login-button')),
      );
      await tester.pump();
      expect(gateway.requestedProviders, [SocialAuthProvider.kakao]);

      completion.answer.complete(readyAccountStatus);
      await tester.pumpAndSettle();
      expect(_currentRoute(tester), AppRoute.home);
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

      // A login that came back and could not be finished over a dead
      // connection is said too, as the connection.
      gateway.emitError(
        ReturnedLoginFailure(ConnectionFailure(TimeoutException('offline'))),
      );
      // Past the notice before it, which leaves first.
      await tester.pumpAndSettle();
      expect(find.textContaining('네트워크 연결이 불안정해요'), findsOneWidget);
      expect(find.textContaining('로그인을 완료하지 못했어요'), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('without an auth gateway the app opens login', (tester) async {
      useTestViewport(tester);

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
    /// Opens 약관 및 정책 with [notifications] and asks for the withdrawal.
    Future<void> withdraw(
      WidgetTester tester,
      FakeSocialAuthGateway auth,
      FakeAccountDeletionGateway deletion,
      NotificationAccess notifications,
    ) async {
      useTestViewport(tester);
      openAppAtDebugRoute(AppRoute.policy);
      await tester.pumpWidget(
        App(
          socialAuthGateway: auth,
          accountDeletionGateway: deletion,
          notificationAccess: notifications,
        ),
      );
      await tester.pumpAndSettle();
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
    }

    testWidgets('deleting the account forgets this phone while still signed '
        'in, then returns to login without a second sign-out', (tester) async {
      final auth = newAuthGateway();
      final steps = <String>[];
      final deletion = FakeAccountDeletionGateway(
        const AccountDeletionStatus(state: 'active'),
      )..afterScheduled = () async => steps.add('withdrawal');
      final notifications = _PhoneNotifications(steps);

      await withdraw(tester, auth, deletion, notifications);
      await tester.pumpAndSettle();

      expect(steps, <String>['forget', 'withdrawal']);
      expect(auth.signOutRequests, 0);
      expect(_currentRoute(tester), AppRoute.appLogin);
      expect(find.text('계정 삭제가 접수됐어요. 7일 이내에 다시 로그인하면 복구돼요.'), findsOneWidget);
    });

    testWidgets('a withdrawal says it was received, never that the member was '
        'signed out, even when the end of the session is announced late', (
      tester,
    ) async {
      final auth = newAuthGateway();
      // The real gateway ends this phone's session itself; the client may
      // say so after the withdrawal has already left the account.
      final deletion =
          FakeAccountDeletionGateway(
              const AccountDeletionStatus(state: 'active'),
            )
            ..afterScheduled = () async => Timer(
              Duration.zero,
              () => auth.emit(SocialAuthSessionEvent.signedOut),
            );

      await withdraw(tester, auth, deletion, _PhoneNotifications(<String>[]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(deletion.deletions, 1);
      expect(_currentRoute(tester), AppRoute.appLogin);
      expect(find.text('계정 삭제가 접수됐어요. 7일 이내에 다시 로그인하면 복구돼요.'), findsOneWidget);
      expect(find.textContaining('로그아웃됐어요'), findsNothing);
      expect(find.textContaining('처리하지 못했어요'), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a withdrawal the server refuses keeps the member and makes '
        'this phone known again', (tester) async {
      final auth = newAuthGateway();
      final steps = <String>[];
      final deletion =
          FakeAccountDeletionGateway(
              const AccountDeletionStatus(state: 'active'),
            )
            ..afterScheduled = () async => throw const AccountDeletionException(
              '현재 로그인된 소셜 계정과 일치하지 않아요.',
            );

      await withdraw(tester, auth, deletion, _PhoneNotifications(steps));
      await tester.pumpAndSettle();

      expect(steps, <String>['forget', 'resume']);
      expect(_currentRoute(tester), AppRoute.policy);
      expect(find.text('현재 로그인된 소셜 계정과 일치하지 않아요.'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets(
      'signing in within the 30 days restores the account without asking',
      (tester) async {
        final deletion = FakeAccountDeletionGateway(
          AccountDeletionStatus(
            state: 'scheduled',
            canRestore: true,
            deadline: DateTime(2026, 12, 1),
          ),
        );
        final completion = FakeAccountCompletionGateway(
          status: readyAccountStatus,
        );
        final gateway = await _pumpApp(
          tester,
          accountCompletion: completion,
          cardCount: _cardCount(1),
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
        expect(find.byType(AccountDeletingDialog), findsNothing);
        expect(find.text('삭제가 취소되고 계정이 복구됐어요.'), findsOneWidget);
        expect(_currentRoute(tester), AppRoute.home);
      },
    );

    testWidgets(
      'a session past the 30 days is told of the deletion and signed out',
      (tester) async {
        final deletion = FakeAccountDeletionGateway(
          const AccountDeletionStatus(state: 'scheduled'),
        );
        final gateway = await _pumpApp(
          tester,
          accountCompletion: FakeAccountCompletionGateway(
            status: readyAccountStatus,
          ),
          cardCount: _cardCount(1),
          accountDeletion: deletion,
        );

        gateway.emit(SocialAuthSessionEvent.initialSession);
        await tester.pumpAndSettle();

        expect(find.byType(AccountDeletingDialog), findsOneWidget);
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
      expect(
        find.byKey(const ValueKey<String>('profile-interest-settings')),
        findsOneWidget,
      );
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
      expect(find.text('로그아웃 확인'), findsOneWidget);
      expect(find.text('로그인 상태가 해제돼요.'), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
      expect(find.text('취소'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('policy-sign-out-confirm')),
      );
      await tester.pumpAndSettle();

      expect(gateway.signOutRequests, 1);
      expect(_currentRoute(tester), AppRoute.appLogin);
    });
  });
}
