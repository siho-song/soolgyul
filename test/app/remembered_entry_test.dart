import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/core/kept_first.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/home/presentation/home_screen.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/account_deletion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_preferences_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_setup_draft.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';
import '../support/memory_saved_views.dart';

// A member the phone remembers opens on home at once, from what the phone
// kept; the account is asked about behind home.

const _ready = AccountCompletionStatus(
  profileComplete: true,
  displayName: '민지',
  adultAgeConfirmed: true,
  termsVersion: AccountPolicyVersions.terms,
  privacyVersion: AccountPolicyVersions.privacy,
  marketingOptIn: false,
  deletionState: 'active',
);

ProfilePreferences _profile(String name) => ProfilePreferences(
  displayName: name,
  interests: const <DrinkInterest>{DrinkInterest.wine},
  gender: ProfileGender.female,
);

/// Answers the profile when [server] is completed; [onPhone] is the copy
/// kept from last time.
class _Profile
    implements ProfilePreferencesGateway, KeepsLast<ProfilePreferences> {
  ProfilePreferences? onPhone;
  final Completer<ProfilePreferences> server = Completer<ProfilePreferences>();
  int fetches = 0;

  @override
  Future<ProfilePreferences?> kept() async => onPhone;

  @override
  Future<ProfilePreferences> fetchProfilePreferences() {
    fetches += 1;
    return server.future;
  }

  @override
  Future<String> updateDisplayName(String displayName) async => displayName;

  @override
  Future<Set<DrinkInterest>> replaceDrinkInterests(
    Set<DrinkInterest> interests,
  ) async => interests;
}

/// Answers the sign-up state when [server] is completed.
class _Completion implements AccountCompletionGateway {
  final Completer<AccountCompletionStatus> server =
      Completer<AccountCompletionStatus>();
  int fetches = 0;

  @override
  Future<AccountCompletionStatus> fetchStatus() {
    fetches += 1;
    return server.future;
  }

  @override
  Future<AccountCompletionStatus> complete(CompleteAccountRequest request) =>
      throw UnimplementedError();
}

/// Answers the deletion state when [server] is completed.
class _Deletion implements AccountDeletionGateway {
  final Completer<AccountDeletionStatus> server =
      Completer<AccountDeletionStatus>();

  @override
  Future<AccountDeletionStatus> fetchStatus() => server.future;

  @override
  Future<void> requestDeletion() async {}

  @override
  Future<void> restore() async {}
}

AppRoute _route(WidgetTester tester) =>
    AppRouterScope.of(tester.element(find.byType(AppFlow))).currentRoute;

void main() {
  late MemorySavedViews phone;
  late _Profile profile;
  late _Completion completion;
  late _Deletion deletion;
  late FakeSocialAuthGateway auth;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = defaultAppTestViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    auth = FakeSocialAuthGateway();
    addTearDown(auth.close);
    await tester.pumpWidget(
      App(
        socialAuthGateway: auth,
        profilePreferencesGateway: profile,
        accountCompletionGateway: completion,
        accountDeletionGateway: deletion,
        profileSummaryLoader: () async => const ProfileSummary(
          cardCount: 1,
          savedArticleCount: 0,
          likedCardCount: 0,
        ),
        savedViews: phone,
      ),
    );
    await tester.pump();
    auth.emit(SocialAuthSessionEvent.initialSession);
    await tester.pump();
    await tester.pump();
  }

  /// Made inside the test: an answer completed there must be heard there.
  void prepare() {
    phone = MemorySavedViews();
    profile = _Profile();
    completion = _Completion();
    deletion = _Deletion();
  }

  Future<void> remember() async {
    await phone.write('entered', <String, Object?>{'ready': true});
    profile.onPhone = _profile('민지');
  }

  testWidgets('a remembered member is on home before the account is asked', (
    tester,
  ) async {
    prepare();
    await remember();
    await open(tester);

    // Neither the deletion state nor the sign-up state has answered.
    expect(_route(tester), AppRoute.home);
    expect(find.byType(HomeScreen), findsOneWidget);

    deletion.server.complete(const AccountDeletionStatus(state: 'active'));
    completion.server.complete(_ready);
    profile.server.complete(_profile('민지'));
    await tester.pumpAndSettle();

    expect(_route(tester), AppRoute.home);
    expect(completion.fetches, 1);
    expect(
      profile.fetches,
      1,
      reason: 'the profile is still asked, behind home',
    );
  });

  testWidgets('a member the phone does not remember waits for the account', (
    tester,
  ) async {
    prepare();
    await open(tester);
    expect(_route(tester), AppRoute.appLoading);

    deletion.server.complete(const AccountDeletionStatus(state: 'active'));
    completion.server.complete(_ready);
    profile.server.complete(_profile('민지'));
    await tester.pumpAndSettle();

    expect(_route(tester), AppRoute.home);
    expect(await phone.read('entered'), <String, Object?>{
      'ready': true,
    }, reason: 'the next launch may open home at once');
  });

  testWidgets('behind home, an account set to be deleted leaves home', (
    tester,
  ) async {
    prepare();
    await remember();
    await open(tester);
    expect(_route(tester), AppRoute.home);

    deletion.server.complete(const AccountDeletionStatus(state: 'active'));
    completion.server.complete(
      const AccountCompletionStatus(
        profileComplete: true,
        displayName: '민지',
        adultAgeConfirmed: true,
        termsVersion: AccountPolicyVersions.terms,
        privacyVersion: AccountPolicyVersions.privacy,
        marketingOptIn: false,
        deletionState: 'scheduled',
      ),
    );
    await tester.pumpAndSettle();

    expect(_route(tester), AppRoute.appLogin);
    expect(find.textContaining('탈퇴 대기 중인 계정이에요'), findsOneWidget);
    expect(await phone.read('entered'), isNull);
  });

  testWidgets('behind home, an unfinished profile goes back to profile setup', (
    tester,
  ) async {
    prepare();
    await remember();
    await open(tester);

    deletion.server.complete(const AccountDeletionStatus(state: 'active'));
    completion.server.complete(
      const AccountCompletionStatus(
        profileComplete: false,
        displayName: '민지',
        adultAgeConfirmed: false,
        termsVersion: null,
        privacyVersion: null,
        marketingOptIn: false,
        deletionState: 'active',
      ),
    );
    profile.server.complete(_profile('민지'));
    await tester.pumpAndSettle();

    expect(_route(tester), AppRoute.profileSetup);
  });

  testWidgets('behind home, a server that cannot be reached changes nothing', (
    tester,
  ) async {
    prepare();
    await remember();
    await open(tester);

    deletion.server.completeError(StateError('offline'));
    completion.server.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(_route(tester), AppRoute.home);
    expect(find.textContaining('확인하지 못했어요'), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    expect(await phone.read('entered'), isNotNull);
  });

  testWidgets('behind home, an account check that fails changes nothing', (
    tester,
  ) async {
    prepare();
    await remember();
    await open(tester);

    // The server answered with an error; that is not the end of a sign-in.
    deletion.server.completeError(
      const AccountDeletionException('계정 상태를 확인하지 못했어요.'),
    );
    completion.server.completeError(StateError('server error'));
    await tester.pumpAndSettle();

    expect(auth.signOutRequests, 0);
    expect(_route(tester), AppRoute.home);
    expect(await phone.read('entered'), isNotNull);
  });

  testWidgets('a kept profile without the entered mark is not enough', (
    tester,
  ) async {
    prepare();
    profile.onPhone = _profile('민지');
    await open(tester);

    expect(_route(tester), AppRoute.appLoading);
  });

  testWidgets('signing out forgets what the phone kept', (tester) async {
    prepare();
    await remember();
    await phone.write('letters', <String, Object?>{'record_count': 3});
    await open(tester);
    deletion.server.complete(const AccountDeletionStatus(state: 'active'));
    completion.server.complete(_ready);
    profile.server.complete(_profile('민지'));
    await tester.pumpAndSettle();

    AppRouterScope.of(
      tester.element(find.byType(AppFlow)),
    ).replaceRoot(AppRoute.policy);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('policy-sign-out')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('policy-sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('policy-sign-out-confirm')),
    );
    await tester.pumpAndSettle();

    expect(auth.signOutRequests, 1);
    expect(_route(tester), AppRoute.appLogin);
    expect(phone.copies, isEmpty);
  });
}
