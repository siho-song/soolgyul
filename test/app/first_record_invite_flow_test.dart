import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/home/data/taste_letters.dart';
import 'package:soolgyul/src/features/home/presentation/home_screens.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_draft.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';

const _readyAccount = AccountCompletionStatus(
  profileComplete: true,
  displayName: '민지',
  adultAgeConfirmed: true,
  termsVersion: AccountPolicyVersions.terms,
  privacyVersion: AccountPolicyVersions.privacy,
  marketingOptIn: false,
  deletionState: 'active',
);

/// The letters of a member with [records] records.
class _Letters implements TasteLettersGateway {
  _Letters(this.records);
  final int records;

  @override
  Future<TasteLettersSnapshot> load() async => TasteLettersSnapshot(
    state: TasteLettersState(axes: const {}, recordCount: records),
  );
}

const _invite = ValueKey<String>('first-record-invite');
const _start = ValueKey<String>('first-record-invite-start');

AppRoute _currentRoute(WidgetTester tester) =>
    AppRouterScope.of(tester.element(find.byType(AppFlow))).currentRoute;

/// Opens the app on the home of a signed-in member with [records] records.
Future<void> _openHome(WidgetTester tester, {required int records}) async {
  tester.view.physicalSize = defaultAppTestViewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final gateway = FakeSocialAuthGateway();
  addTearDown(gateway.close);
  await tester.pumpWidget(
    App(
      socialAuthGateway: gateway,
      accountCompletionGateway: FakeAccountCompletionGateway(
        status: _readyAccount,
      ),
      sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
      tasteLettersGateway: _Letters(records),
      cardCountLoader: () async => records,
    ),
  );
  await tester.pump();
  gateway.emit(SocialAuthSessionEvent.initialSession);
  await tester.pumpAndSettle();
  expect(_currentRoute(tester), AppRoute.home);
}

void main() {
  testWidgets('a member without a record starts the first record from the '
      'home\'s invite, at the drink search', (tester) async {
    await _openHome(tester, records: 0);

    expect(find.byKey(_invite), findsOneWidget);
    expect(find.byType(TasteFitSearchEntry), findsNothing);
    expect(find.byType(SoolgyulLettersCard), findsNothing);

    await tester.ensureVisible(find.byKey(_start));
    await tester.tap(find.byKey(_start));
    await tester.pumpAndSettle();

    // Past the welcome page, as from the bottom bar's 기록 button.
    expect(_currentRoute(tester), AppRoute.onboardingSearch);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a member with a record has the home as it was', (tester) async {
    await _openHome(tester, records: 2);

    expect(find.byKey(_invite), findsNothing);
    expect(find.byType(TasteFitSearchEntry), findsOneWidget);
    expect(find.byType(SoolgyulLettersCard), findsOneWidget);
  });

  testWidgets('the invite goes on turning while the member stays on the '
      'home, and stops with the home', (tester) async {
    await _openHome(tester, records: 0);

    // Slide after slide for a minute; each settles, so nothing runs on.
    for (var second = 0; second < 60; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(_invite), findsOneWidget);

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    expect(find.byKey(_invite), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });
}
