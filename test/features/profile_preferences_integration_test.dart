import 'package:soolgyul/src/core/errors/connection_failure.dart';
import 'package:soolgyul/src/core/catalog/drink_type.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/catalog/data/suggested_drinks.dart';
import 'package:soolgyul/src/features/onboarding/presentation/widgets/onboarding_actions.dart';
import 'package:soolgyul/src/features/profile/data/profile_preferences_gateway.dart';
import 'package:soolgyul/src/features/profile/presentation/drink_interest_sheet.dart';
import 'package:soolgyul/src/features/profile/presentation/nickname_edit_popup.dart';
import 'package:soolgyul/src/features/profile/presentation/widgets/drink_select_card.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/recording/presentation/drink_search_screen.dart';
import 'package:soolgyul/src/features/taste_fit/presentation/taste_fit_search_screen.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';
import 'package:soolgyul/src/widgets/app_bottom_nav.dart';

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
        interests: const <DrinkType>{},
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
    await completeProfileSetup(tester, name: '첫사용자');

    expect(profileGateway.updatedDisplayNames, isEmpty);
    expect(accountGateway.requests, hasLength(1));
    expect(accountGateway.requests.single.displayName, '첫사용자');
    expect(profileGateway.replacedInterests, <Set<DrinkType>>[
      <DrinkType>{DrinkType.wine},
    ]);
    expect(
      AppRouterScope.of(tester.element(find.byType(AppFlow))).currentRoute,
      AppRoute.home,
    );
    expect(find.text('고민 중인 술이 있나요?'), findsOneWidget);
  });

  /// Opens 관심 주종 from 내 정보 and reads which drinks its sheet has chosen.
  Future<Set<String>> chosenInterests(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-interest-settings')),
    );
    await tester.pumpAndSettle();
    return {
      for (final card in tester.widgetList<DrinkSelectCard>(
        find.byType(DrinkSelectCard),
      ))
        if (card.selected) card.option.label,
    };
  }

  testWidgets('an authenticated session hydrates My Page from the gateway', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '서버민지',
        interests: const <DrinkType>{DrinkType.wine, DrinkType.sake},
      ),
    );
    await pumpSignedInProfile(tester, profileGateway);

    expect(profileGateway.fetchCount, 1);
    expect(find.text('서버민지'), findsOneWidget);
    // The drinks of interest are seen where they are changed.
    expect(await chosenInterests(tester), {'와인', '사케'});
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
          interests: const <DrinkType>{DrinkType.wine},
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
        interests: const <DrinkType>{DrinkType.wine, DrinkType.sake},
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
    // The birth date and gender are still to be answered: they are asked
    // first, and the interests after them come already chosen.
    expect(find.byType(OnboardingDrinkTile), findsNothing);
    await pickEligibleBirthDate(tester);
    await pickGender(tester);
    final interestTiles = tester.widgetList<OnboardingDrinkTile>(
      find.byType(OnboardingDrinkTile),
    );
    final hydratedTiles = interestTiles
        .where((tile) => tile.label == '와인' || tile.label == '사케')
        .toList();
    expect(hydratedTiles, hasLength(2));
    expect(hydratedTiles.every((tile) => tile.selected), isTrue);
  });

  testWidgets('what was typed on the setup page is still there after going '
      'back and logging in again', (tester) async {
    final authGateway = FakeSocialAuthGateway();
    addTearDown(authGateway.close);
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: null,
        interests: const <DrinkType>{},
      ),
    );
    await pumpAppAtRoute(
      tester,
      AppRoute.appLogin,
      defaultAppTestViewport,
      authGateway,
      profileGateway,
      null,
      FakeAccountCompletionGateway(),
    );
    final login = find.byKey(const ValueKey<String>('google-login-button'));
    await tester.tap(login);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '테스터');
    await tester.pump();
    await showNextSetupStep(tester);
    await pickEligibleBirthDate(tester);
    await pickGender(tester);
    await tester.tap(find.text('와인'));
    await tester.pump();

    await tester.tap(find.byTooltip('이전 화면으로 이동'));
    await tester.pumpAndSettle();
    await tester.tap(login);
    await tester.pumpAndSettle();

    // The account was read again, and its empty profile replaced nothing.
    expect(profileGateway.fetchCount, 2);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
      '테스터',
    );
    final wineTile = tester
        .widgetList<OnboardingDrinkTile>(find.byType(OnboardingDrinkTile))
        .singleWhere((tile) => tile.label == '와인');
    expect(wineTile.selected, isTrue);
  });

  testWidgets('hydrate failure shows no made-up profile and reports the '
      'error', (tester) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '사용되지않음',
        interests: const <DrinkType>{DrinkType.whisky},
      ),
      failFetch: true,
    );
    await pumpSignedInProfile(tester, profileGateway);

    expect(profileGateway.fetchCount, 1);
    expect(find.text('민지'), findsNothing);
    expect(find.text('사용되지않음'), findsNothing);
    expect(find.textContaining('프로필 정보를 불러오지 못했어요.'), findsOneWidget);
  });

  testWidgets(
    'nickname save waits for the server before updating and closing',
    (tester) async {
      final profileGateway = _FakeProfilePreferencesGateway(
        preferences: ProfilePreferences(
          displayName: '서버민지',
          interests: const <DrinkType>{DrinkType.wine},
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
        interests: const <DrinkType>{DrinkType.wine},
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

    expect(find.byType(NicknameEditPopup), findsOneWidget);
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
        interests: const <DrinkType>{DrinkType.wine},
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
    expect(find.byType(NicknameEditPopup), findsOneWidget);

    pendingUpdate.complete('중복방지');
    await tester.pumpAndSettle();
    expect(find.byType(NicknameEditPopup), findsNothing);
    expect(find.text('중복방지'), findsOneWidget);
  });

  testWidgets('the keyboard of the nickname popup leaves 내 정보 and its '
      'bottom menu where they were', (tester) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '서버민지',
        interests: const <DrinkType>{DrinkType.wine},
      ),
    );
    await pumpSignedInProfile(tester, profileGateway);
    final menu = find.byType(AppBottomNav);
    final name = find.byKey(const ValueKey<String>('profile-nickname'));
    final before = (tester.getRect(menu), tester.getRect(name));

    await tester.tap(
      find.byKey(const ValueKey<String>('profile-nickname-edit')),
    );
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(find.byType(NicknameEditPopup), findsOneWidget);
    expect((tester.getRect(menu), tester.getRect(name)), before);
  });

  testWidgets('interest replacement updates My Page only after success', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '서버민지',
        interests: const <DrinkType>{DrinkType.wine},
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
    expect(profileGateway.replacedInterests.single, <DrinkType>{
      DrinkType.wine,
      DrinkType.sake,
    });
    expect(navigation.currentRoute, AppRoute.profile);
    expect(find.byType(DrinkInterestSheet), findsNothing);
    expect(await chosenInterests(tester), {'와인', '사케'});
  });

  testWidgets('interest replacement is atomic and failure does not close', (
    tester,
  ) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: '서버민지',
        interests: const <DrinkType>{DrinkType.wine},
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
    expect(profileGateway.replacedInterests.single, <DrinkType>{
      DrinkType.wine,
      DrinkType.sake,
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
        interests: const <DrinkType>{},
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
    await completeProfileSetup(tester, name: '재시도사용자');

    final navigation = AppRouterScope.of(tester.element(find.byType(AppFlow)));
    expect(navigation.currentRoute, AppRoute.profileSetup);
    final wineTile = tester
        .widgetList<OnboardingDrinkTile>(find.byType(OnboardingDrinkTile))
        .singleWhere((tile) => tile.label == '와인');
    expect(wineTile.selected, isTrue);
    expect(profileGateway.updatedDisplayNames, isEmpty);
    expect(accountGateway.requests, isEmpty);
    expect(profileGateway.replacedInterests, <Set<DrinkType>>[
      <DrinkType>{DrinkType.wine},
    ]);
    // Said on the page and, over it, in the agreements sheet, which stays
    // open with its checks for another try.
    expect(find.textContaining('프로필 설정을 저장하지 못했어요.'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('profile-setup-save-feedback')),
      findsOneWidget,
    );
    await startFromSetupAgreements(tester);
    expect(profileGateway.replacedInterests, hasLength(2));
  });

  testWidgets('a profile setup the connection kept from saving says the '
      'connection, on the page\'s notice and in the sheet', (tester) async {
    final profileGateway = _FakeProfilePreferencesGateway(
      preferences: ProfilePreferences(
        displayName: null,
        interests: const <DrinkType>{},
      ),
      failInterestReplacement: true,
      failureCause: ConnectionFailure('no route'),
    );
    await pumpAppAtRoute(
      tester,
      AppRoute.profileSetup,
      defaultAppTestViewport,
      null,
      profileGateway,
      null,
      FakeAccountCompletionGateway(),
    );
    await completeProfileSetup(tester, name: '재시도사용자');

    expect(find.textContaining('네트워크 연결이 불안정해요'), findsNWidgets(2));
    expect(find.textContaining('프로필 설정을 저장하지 못했어요.'), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('profile-setup-save-feedback')),
          )
          .data,
      '네트워크 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.',
    );
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
    this.failureCause,
  });

  /// What a failing replacement of the interests was told.
  final Object? failureCause;

  final ProfilePreferences preferences;
  final String? storedDisplayName;
  final bool failFetch;
  final bool failDisplayNameUpdate;
  final bool failInterestReplacement;
  final Completer<String>? pendingDisplayNameUpdate;
  final List<String> updatedDisplayNames = <String>[];
  final List<Set<DrinkType>> replacedInterests = <Set<DrinkType>>[];
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
  Future<Set<DrinkType>> replaceDrinkInterests(Set<DrinkType> interests) async {
    replacedInterests.add(Set<DrinkType>.of(interests));
    if (failInterestReplacement) {
      throw ProfilePreferencesException(
        ProfilePreferencesOperation.replaceDrinkInterests,
        cause: failureCause,
      );
    }
    return Set<DrinkType>.unmodifiable(interests);
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
