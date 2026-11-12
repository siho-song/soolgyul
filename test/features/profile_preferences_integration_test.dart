import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/catalog/data/suggested_drinks.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_actions.dart';
import 'package:soolgyul/src/features/profile/data/profile_preferences_gateway.dart';
import 'package:soolgyul/src/features/profile/presentation/drink_interest_sheet.dart';
import 'package:soolgyul/src/features/profile/presentation/nickname_edit_sheet.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/recording/presentation/drink_search_screen.dart';
import 'package:soolgyul/src/features/profile/data/profile_setup_draft.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';

/// Opens My Page with a signed-in session whose profile comes from [gateway].
Future<void> pumpSignedInProfile(
  WidgetTester tester,
  ProfilePreferencesGateway gateway,
) async {
  final authGateway = FakeSocialAuthGateway();
  addTearDown(authGateway.close);
  await pumpAppAtRoute(
    tester,
    AppRoute.profile,
    defaultAppTestViewport,
    authGateway,
    gateway,
  );
  authGateway.emit(SocialAuthSessionEvent.initialSession);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('post-login profile setup persists name and interests', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: null,
        interests: const <DrinkInterest>{},
      ),
    );
    final accountGateway = FakeAccountCompletionGateway();

    await pumpAppAtRoute(
      tester,
      AppRoute.profileSetup,
      defaultAppTestViewport,
      null,
      profileGateway,
      null,
      accountGateway,
    );
    await tester.enterText(find.byType(TextFormField), '첫사용자');
    await tester.pump();
    await tester.ensureVisible(find.text('와인'));
    await tester.tap(find.text('와인'));
    await tester.pump();
    await completeRequiredAccountConfirmation(tester);

    expect(profileGateway.updatedDisplayNames, isEmpty);
    expect(accountGateway.requests, hasLength(1));
    expect(accountGateway.requests.single.displayName, '첫사용자');
    expect(profileGateway.replacedInterests, <Set<DrinkInterest>>[
      <DrinkInterest>{DrinkInterest.wine},
    ]);
    expect(
      AppRouterScope.of(tester.element(find.byType(AppFlow))).currentRoute,
      AppRoute.home,
    );
    expect(find.text('고민 중인 술이 있나요?'), findsOneWidget);
  });

  testWidgets('an authenticated session hydrates My Page from the gateway', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '서버민지',
        interests: const <DrinkInterest>{
          DrinkInterest.wine,
          DrinkInterest.sake,
        },
      ),
    );
    await pumpSignedInProfile(tester, profileGateway);

    expect(profileGateway.fetchCount, 1);
    expect(find.text('서버민지'), findsOneWidget);
    expect(find.text('와인'), findsOneWidget);
    expect(find.text('사케'), findsOneWidget);
  });

  // 자주 찾는 술 on the three search pages, for a signed-in woman: the two
  // member pages follow her gender, onboarding keeps its one list.
  for (final (route, expected) in <(AppRoute, List<String>)>[
    (AppRoute.recordSearch, femaleSuggestedDrinkNames),
    (AppRoute.tasteFitSearch, femaleSuggestedDrinkNames),
    (AppRoute.onboardingSearch, maleSuggestedDrinkNames),
  ]) {
    testWidgets('a woman member on ${route.name} sees its 자주 찾는 술', (
      tester,
    ) async {
      final authGateway = FakeSocialAuthGateway();
      final profileGateway = _FakeProfilePreferencesGateway(
        preferences: ProfilePreferences(
          displayName: '서버민지',
          interests: const <DrinkInterest>{DrinkInterest.wine},
          gender: ProfileGender.female,
        ),
      );
      addTearDown(authGateway.close);

      await pumpAppAtRoute(
        tester,
        route,
        defaultAppTestViewport,
        authGateway,
        profileGateway,
      );
      List<String> shown() => route == AppRoute.tasteFitSearch
          ? tester
                .widget<TasteFitSearchScreen>(find.byType(TasteFitSearchScreen))
                .suggestedDrinkNames
          : tester
                .widget<RecordDrinkSearchScreen>(
                  find.byType(RecordDrinkSearchScreen),
                )
                .suggestedDrinkNames;
      // Before the profile is read the member counts as a guest.
      expect(shown(), maleSuggestedDrinkNames);

      authGateway.emit(SocialAuthSessionEvent.initialSession);
      await tester.pumpAndSettle();
      expect(profileGateway.fetchCount, 1);
      expect(shown(), expected);
    });
  }

  testWidgets('an existing profile prefills post-login setup', (tester) async {
    final authGateway = FakeSocialAuthGateway();
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '기존사용자',
        interests: const <DrinkInterest>{
          DrinkInterest.wine,
          DrinkInterest.sake,
        },
      ),
    );
    addTearDown(authGateway.close);

    // An account that has not finished signing up opens profile setup.
    await pumpAppAtRoute(
      tester,
      AppRoute.appLogin,
      defaultAppTestViewport,
      authGateway,
      profileGateway,
      null,
      FakeAccountCompletionGateway(),
    );
    authGateway.emit(SocialAuthSessionEvent.signedIn);
    await tester.pumpAndSettle();

    expect(profileGateway.fetchCount, 1);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
      '기존사용자',
    );
    final interestTiles = tester.widgetList<OnboardingDrinkTile>(
      find.byType(OnboardingDrinkTile),
    );
    final hydratedTiles = interestTiles
        .where((tile) => tile.label == '와인' || tile.label == '사케')
        .toList();
    expect(hydratedTiles, hasLength(2));
    expect(hydratedTiles.every((tile) => tile.selected), isTrue);
  });

  testWidgets('hydrate failure keeps fixture state and reports the error', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '사용되지않음',
        interests: const <DrinkInterest>{DrinkInterest.whisky},
      ),
      failFetch: true,
    );
    await pumpSignedInProfile(tester, profileGateway);

    expect(profileGateway.fetchCount, 1);
    expect(find.text('민지'), findsOneWidget);
    expect(find.textContaining('프로필 정보를 불러오지 못했어요.'), findsOneWidget);
  });

  testWidgets(
    'nickname save waits for the server before updating and closing',
    (tester) async {
      final profileGateway = _FakeProfilePreferencesGateway(
        preferences: ProfilePreferences(
          displayName: '서버민지',
          interests: const <DrinkInterest>{DrinkInterest.wine},
        ),
        storedDisplayName: '정규화닉네임',
      );
      await pumpSignedInProfile(tester, profileGateway);
      await tester.tap(
        find.byKey(const ValueKey<String>('profile-nickname-edit')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('profile-nickname-field')),
        '새닉네임',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('profile-save-button')),
      );
      await tester.pumpAndSettle();

      final navigation = AppRouterScope.of(
        tester.element(find.byType(AppFlow)),
      );
      expect(profileGateway.updatedDisplayNames, <String>['새닉네임']);
      expect(navigation.currentRoute, AppRoute.profile);
      expect(find.text('정규화닉네임'), findsOneWidget);
    },
  );

  testWidgets('nickname failure keeps the sheet open and shows an error', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '서버민지',
        interests: const <DrinkInterest>{DrinkInterest.wine},
      ),
      failDisplayNameUpdate: true,
    );
    await pumpSignedInProfile(tester, profileGateway);
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-nickname-edit')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile-nickname-field')),
      '실패닉네임',
    );
    await tester.tap(find.byKey(const ValueKey<String>('profile-save-button')));
    await tester.pumpAndSettle();

    expect(find.byType(NicknameEditSheet), findsOneWidget);
    expect(find.textContaining('저장하지 못했어요.'), findsOneWidget);
    expect(find.text('서버민지'), findsOneWidget);
  });

  testWidgets('nickname save ignores duplicate taps while RPC is pending', (
    tester,
  ) async {
    final pendingUpdate = Completer<String>();
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '서버민지',
        interests: const <DrinkInterest>{DrinkInterest.wine},
      ),
      pendingDisplayNameUpdate: pendingUpdate,
    );
    await pumpSignedInProfile(tester, profileGateway);
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-nickname-edit')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile-nickname-field')),
      '중복방지',
    );
    final saveButton = find.byKey(
      const ValueKey<String>('profile-save-button'),
    );
    await tester.tap(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pump();

    expect(profileGateway.updatedDisplayNames, <String>['중복방지']);
    expect(find.byType(NicknameEditSheet), findsOneWidget);

    pendingUpdate.complete('중복방지');
    await tester.pumpAndSettle();
    expect(find.byType(NicknameEditSheet), findsNothing);
    expect(find.text('중복방지'), findsOneWidget);
  });

  testWidgets('interest replacement updates My Page only after success', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '서버민지',
        interests: const <DrinkInterest>{DrinkInterest.wine},
      ),
    );
    await pumpSignedInProfile(tester, profileGateway);
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-interest-settings')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('profile-drink-사케')));
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-drink-complete')),
    );
    await tester.pumpAndSettle();

    final navigation = AppRouterScope.of(tester.element(find.byType(AppFlow)));
    expect(profileGateway.replacedInterests.single, <DrinkInterest>{
      DrinkInterest.wine,
      DrinkInterest.sake,
    });
    expect(navigation.currentRoute, AppRoute.profile);
    expect(find.text('와인'), findsOneWidget);
    expect(find.text('사케'), findsOneWidget);
  });

  testWidgets('interest replacement is atomic and failure does not close', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '서버민지',
        interests: const <DrinkInterest>{DrinkInterest.wine},
      ),
      failInterestReplacement: true,
    );
    await pumpSignedInProfile(tester, profileGateway);
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-interest-settings')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('profile-drink-사케')));
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-drink-complete')),
    );
    await tester.pumpAndSettle();

    final navigation = AppRouterScope.of(tester.element(find.byType(AppFlow)));
    expect(profileGateway.replacedInterests.single, <DrinkInterest>{
      DrinkInterest.wine,
      DrinkInterest.sake,
    });
    expect(navigation.currentRoute, AppRoute.profile);
    expect(find.byType(DrinkInterestSheet), findsOneWidget);
    expect(find.textContaining('관심 주종을 저장하지 못했어요.'), findsOneWidget);
  });

  testWidgets('profile setup failure keeps the draft and setup route', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: null,
        interests: const <DrinkInterest>{},
      ),
      failInterestReplacement: true,
    );
    final accountGateway = FakeAccountCompletionGateway();

    await pumpAppAtRoute(
      tester,
      AppRoute.profileSetup,
      defaultAppTestViewport,
      null,
      profileGateway,
      null,
      accountGateway,
    );
    await tester.enterText(find.byType(TextFormField), '재시도사용자');
    await tester.pump();
    await tester.ensureVisible(find.text('와인'));
    await tester.tap(find.text('와인'));
    await tester.pump();
    await completeRequiredAccountConfirmation(tester);

    final navigation = AppRouterScope.of(tester.element(find.byType(AppFlow)));
    expect(navigation.currentRoute, AppRoute.profileSetup);
    final wineTile = tester
        .widgetList<OnboardingDrinkTile>(find.byType(OnboardingDrinkTile))
        .singleWhere((tile) => tile.label == '와인');
    expect(wineTile.selected, isTrue);
    expect(profileGateway.updatedDisplayNames, isEmpty);
    expect(accountGateway.requests, isEmpty);
    expect(profileGateway.replacedInterests, <Set<DrinkInterest>>[
      <DrinkInterest>{DrinkInterest.wine},
    ]);
    expect(find.textContaining('프로필 설정을 저장하지 못했어요.'), findsOneWidget);
  });
}

class _FakeProfilePreferencesGateway implements ProfilePreferencesGateway {
  _FakeProfilePreferencesGateway({
    required this.preferences,
    this.storedDisplayName,
    this.failFetch = false,
    this.failDisplayNameUpdate = false,
    this.failInterestReplacement = false,
    this.pendingDisplayNameUpdate,
  });

  final ProfilePreferences preferences;
  final String? storedDisplayName;
  final bool failFetch;
  final bool failDisplayNameUpdate;
  final bool failInterestReplacement;
  final Completer<String>? pendingDisplayNameUpdate;
  final List<String> updatedDisplayNames = <String>[];
  final List<Set<DrinkInterest>> replacedInterests = <Set<DrinkInterest>>[];
  int fetchCount = 0;

  @override
  Future<ProfilePreferences> fetchProfilePreferences() async {
    fetchCount += 1;
    if (failFetch) {
      throw const ProfilePreferencesException(
        ProfilePreferencesOperation.fetch,
      );
    }
    return preferences;
  }

  @override
  Future<Set<DrinkInterest>> replaceDrinkInterests(
    Set<DrinkInterest> interests,
  ) async {
    replacedInterests.add(Set<DrinkInterest>.of(interests));
    if (failInterestReplacement) {
      throw const ProfilePreferencesException(
        ProfilePreferencesOperation.replaceDrinkInterests,
      );
    }
    return Set<DrinkInterest>.unmodifiable(interests);
  }

  @override
  Future<String> updateDisplayName(String displayName) async {
    updatedDisplayNames.add(displayName);
    if (failDisplayNameUpdate) {
      throw const ProfilePreferencesException(
        ProfilePreferencesOperation.updateDisplayName,
      );
    }
    final pendingUpdate = pendingDisplayNameUpdate;
    if (pendingUpdate != null) {
      return pendingUpdate.future;
    }
    return storedDisplayName ?? displayName;
  }
}
