import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/home/data/next_drink_guides.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/features/onboarding/data/sensory_questionnaire_data.dart';
import 'package:soolgyul/src/features/profile/data/profile_preferences_gateway.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/account_deletion_gateway.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/records/data/record_note_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import 'test_catalog.dart';

const Size defaultAppTestViewport = Size(411, 891);

class _SensoryTestAssets extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      File(key).readAsStringSync();

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

/// Explicit local catalog evidence for navigation tests; never calls Supabase.
Future<SensoryQuestionnaireData> loadTestSensoryQuestionnaire(
  DrinkSelection selection,
) {
  final (category, style) = switch (selection.category) {
    DrinkCategory.redWine => ('wine', 'red_wine'),
    DrinkCategory.whiteWine => ('wine', 'white_wine'),
    DrinkCategory.sparklingWine => ('wine', 'sparkling_wine'),
    DrinkCategory.whisky => ('whisky', 'single_malt_whisky'),
    DrinkCategory.sake => ('sake', 'junmai'),
    DrinkCategory.koreanTraditional => ('korean_traditional', 'takju'),
    DrinkCategory.other => ('wine', null),
  };
  return SensoryQuestionnaireDataSource(
    assets: _SensoryTestAssets(),
    readContext: (id) async => {
      'id': id,
      'name': selection.displayName,
      'category': category,
      'style_key': style,
      'aroma_keys': selection.category == DrinkCategory.whisky
          ? ['peat', 'smoke', 'oak', 'vanilla']
          : ['cherry', 'apple', 'floral'],
      'sensory_scale': 5,
      'levels': <String, int>{},
    },
  ).load(selection);
}

Future<void> tapSensoryOption(WidgetTester tester, String key) async {
  final option = find.byKey(ValueKey(key));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

/// Answers as little as a record takes after 재음용 의사: the nose is left
/// by the header's SKIP and the palate by 다음, the finish takes the one
/// sensation a record needs (여운의 길이 3), and the review's 저장 sends
/// the record with that answer liked.
Future<void> completeSensoryQuestionsWithOneAnswer(WidgetTester tester) async {
  await tapSensoryOption(tester, 'nose:unsure');
  expect(find.byKey(const ValueKey('sensory-step:palate')), findsOneWidget);
  await tapSensoryOption(tester, 'sensory-next');
  expect(find.byKey(const ValueKey('sensory-step:finish')), findsOneWidget);
  await tapSensoryOption(tester, 'gauge:finish_length:3');
  await tapSensoryOption(tester, 'sensory-next');
  expect(find.byKey(const ValueKey('sensory-step:review')), findsOneWidget);
  await tapSensoryOption(tester, 'sensory-next');
}

class FakeSocialAuthGateway implements SocialAuthGateway {
  FakeSocialAuthGateway({
    this.result = SocialAuthResult.authenticated,
    this.signedInProvider,
  });

  final SocialAuthResult result;

  @override
  SocialAuthProvider? signedInProvider;
  final List<SocialAuthProvider> requestedProviders = <SocialAuthProvider>[];
  int signOutRequests = 0;
  final StreamController<SocialAuthSessionEvent> _events =
      StreamController<SocialAuthSessionEvent>.broadcast(sync: true);

  @override
  Stream<SocialAuthSessionEvent> get sessionEvents => _events.stream;

  @override
  Future<SocialAuthResult> signIn(SocialAuthProvider provider) async {
    requestedProviders.add(provider);
    return result;
  }

  @override
  Future<void> signOut() async {
    signOutRequests += 1;
    // As the real client does: the end of the session is announced.
    if (!_events.isClosed) _events.add(SocialAuthSessionEvent.signedOut);
  }

  void emit(SocialAuthSessionEvent event) => _events.add(event);

  void emitError(Object error) => _events.addError(error, StackTrace.current);

  Future<void> close() => _events.close();
}

class FakeAccountCompletionGateway implements AccountCompletionGateway {
  FakeAccountCompletionGateway({
    this.failureCode,
    AccountCompletionStatus? status,
  }) : status =
           status ??
           const AccountCompletionStatus(
             profileComplete: false,
             displayName: null,
             adultAgeConfirmed: false,
             termsVersion: null,
             privacyVersion: null,
             marketingOptIn: false,
             deletionState: 'active',
           );

  final String? failureCode;
  final AccountCompletionStatus status;
  final List<CompleteAccountRequest> requests = <CompleteAccountRequest>[];
  int statusRequests = 0;

  @override
  Future<AccountCompletionStatus> fetchStatus() async {
    statusRequests += 1;
    return status;
  }

  @override
  Future<AccountCompletionStatus> complete(
    CompleteAccountRequest request,
  ) async {
    requests.add(request);
    if (failureCode != null) {
      throw AccountCompletionException(
        AccountCompletionOperation.complete,
        code: failureCode,
      );
    }
    return AccountCompletionStatus(
      profileComplete: true,
      displayName: request.displayName,
      adultAgeConfirmed: true,
      termsVersion: AccountPolicyVersions.terms,
      privacyVersion: AccountPolicyVersions.privacy,
      marketingOptIn: request.marketingOptIn,
      deletionState: 'active',
    );
  }
}

Future<void> pumpTestScreen(
  WidgetTester tester,
  Widget screen, {
  Size viewport = defaultAppTestViewport,
}) async {
  _configureViewport(tester, viewport);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(body: SafeArea(child: screen)),
    ),
  );
  await tester.pump();
}

Future<void> pumpAppAtDebugScreen(
  WidgetTester tester,
  int debugScreen, [
  Size viewport = defaultAppTestViewport,
  SocialAuthGateway? socialAuthGateway,
  ProfilePreferencesGateway? profilePreferencesGateway,
  TasteCardGateway? tasteCardGateway,
  AccountCompletionGateway? accountCompletionGateway,
  RecordNoteGateway? recordNoteGateway,
  NextDrinkGuidesGateway? nextDrinkGuidesGateway,
  AccountDeletionGateway? accountDeletionGateway,
  PreferenceHistoryGateway? preferenceHistoryGateway,
]) async {
  _configureViewport(tester, viewport);

  const debugScreenChannel = MethodChannel('soolgyul/debug-screen');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        debugScreenChannel,
        (call) async => debugScreen,
      );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(debugScreenChannel, null),
  );

  await tester.pumpWidget(
    App(
      socialAuthGateway: socialAuthGateway,
      profilePreferencesGateway: profilePreferencesGateway,
      catalogSearchGateway: const TestCatalogGateway(),
      tasteCardGateway: tasteCardGateway,
      accountCompletionGateway: accountCompletionGateway,
      recordNoteGateway: recordNoteGateway,
      nextDrinkGuidesGateway: nextDrinkGuidesGateway,
      accountDeletionGateway: accountDeletionGateway,
      preferenceHistoryGateway: preferenceHistoryGateway,
      sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpAppAtRoute(
  WidgetTester tester,
  AppRoute route, [
  Size viewport = defaultAppTestViewport,
  SocialAuthGateway? socialAuthGateway,
  ProfilePreferencesGateway? profilePreferencesGateway,
  TasteCardGateway? tasteCardGateway,
  AccountCompletionGateway? accountCompletionGateway,
  RecordNoteGateway? recordNoteGateway,
  NextDrinkGuidesGateway? nextDrinkGuidesGateway,
  AccountDeletionGateway? accountDeletionGateway,
  PreferenceHistoryGateway? preferenceHistoryGateway,
]) {
  return pumpAppAtDebugScreen(
    tester,
    route.debugScreen,
    viewport,
    socialAuthGateway,
    profilePreferencesGateway,
    tasteCardGateway,
    accountCompletionGateway,
    recordNoteGateway,
    nextDrinkGuidesGateway,
    accountDeletionGateway,
    preferenceHistoryGateway,
  );
}

Future<void> pumpAppAtRecordEntry(
  WidgetTester tester, [
  TasteCardGateway? tasteCardGateway,
  RecordNoteGateway? recordNoteGateway,
]) async {
  await pumpAppAtRoute(
    tester,
    AppRoute.home,
    defaultAppTestViewport,
    null,
    null,
    tasteCardGateway,
    null,
    recordNoteGateway,
  );
  await tester.tap(find.text('기록'));
  await tester.pumpAndSettle();
}

/// Accepts the birth date picker's initial, eligible date. The picker opens
/// by itself when its step appears after the nickname; when it is not open,
/// the field is pressed first.
Future<void> pickEligibleBirthDate(WidgetTester tester) async {
  if (find.text('확인').evaluate().isEmpty) {
    final field = find.byKey(const ValueKey<String>('birth-date-field'));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('확인').last);
  await tester.pumpAndSettle();
}

/// Chooses 여성 in the required gender field.
Future<void> pickGender(WidgetTester tester) async {
  final field = find.byKey(const ValueKey<String>('gender-field'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text('여성').last);
  await tester.pumpAndSettle();
}

/// Presses 다음 on the setup page: its next question shows on top, or,
/// after the last one, the agreements sheet opens.
Future<void> showNextSetupStep(WidgetTester tester) async {
  final next = find.byKey(const ValueKey<String>('profile-setup-next-button'));
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
}

/// Answers the setup page from its first question to the start button in
/// the agreements sheet: [name], an eligible birth date and a gender, 와인,
/// the required agreements and, with [advertising], the optional one.
Future<void> completeProfileSetup(
  WidgetTester tester, {
  required String name,
  bool advertising = false,
}) async {
  await tester.enterText(find.byType(TextFormField), name);
  await tester.pump();
  // The birth date picker opens with the step.
  await showNextSetupStep(tester);
  await pickEligibleBirthDate(tester);
  // The second answer of the two brings the interests by itself.
  await pickGender(tester);
  await tester.ensureVisible(find.text('와인'));
  await tester.tap(find.text('와인'));
  await tester.pump();
  await showNextSetupStep(tester);
  await checkSetupAgreements(tester, advertising: advertising);
  await startFromSetupAgreements(tester);
}

/// Checks the required rows of the open agreements sheet and, with
/// [advertising], the optional one.
Future<void> checkSetupAgreements(
  WidgetTester tester, {
  bool advertising = false,
}) async {
  for (final key in <String>[
    if (advertising) 'marketing-agreement-row',
    'adult-agreement-row',
    'terms-agreement-row',
    'privacy-agreement-row',
  ]) {
    final row = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }
}

/// Presses 술결 시작하기 in the open agreements sheet.
Future<void> startFromSetupAgreements(WidgetTester tester) async {
  final start = find.byKey(const ValueKey<String>('complete-signup-button'));
  await tester.ensureVisible(start);
  await tester.tap(start);
  await tester.pumpAndSettle();
}

Future<void> expectRoutesAtViewport(
  WidgetTester tester,
  Iterable<AppRoute> routes,
  Size viewport,
) async {
  for (final route in routes) {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpAppAtRoute(tester, route, viewport);
    final renderingError = tester.takeException();
    if (renderingError case final FlutterError error) {
      printOnFailure(error.toStringDeep());
    }
    expect(
      renderingError,
      isNull,
      reason: '${route.name} overflowed at $viewport',
    );
  }
}

void _configureViewport(WidgetTester tester, Size viewport) =>
    useTestViewport(tester, viewport);

/// Sizes the test view to [viewport] at pixel ratio 1 and restores it after
/// the test.
void useTestViewport(
  WidgetTester tester, [
  Size viewport = defaultAppTestViewport,
]) {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Makes the app open at [route], as the native debug-screen channel does,
/// until the test ends.
void openAppAtDebugRoute(AppRoute route) {
  const channel = MethodChannel('soolgyul/debug-screen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (_) async => route.debugScreen);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// A [FakeSocialAuthGateway] that is closed when the test ends.
FakeSocialAuthGateway newAuthGateway() {
  final gateway = FakeSocialAuthGateway();
  addTearDown(gateway.close);
  return gateway;
}

/// A finished sign-up whose account is not being deleted.
const readyAccountStatus = AccountCompletionStatus(
  profileComplete: true,
  displayName: '민지',
  adultAgeConfirmed: true,
  termsVersion: AccountPolicyVersions.terms,
  privacyVersion: AccountPolicyVersions.privacy,
  marketingOptIn: false,
  deletionState: 'active',
);

/// Opens the drink-name question from the onboarding welcome page.
Future<void> startOnboarding(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final start = find.byKey(const ValueKey<String>('onboarding-welcome-start'));
  await tester.ensureVisible(start);
  await tester.tap(start);
  await tester.pumpAndSettle();
}
