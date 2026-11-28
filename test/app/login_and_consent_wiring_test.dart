// Passes once agent A's two wiring lines are in app_flow_pages.dart and
// app_flow.dart. Its test belongs in app_entry_flow_test.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/features/profile/data/account_completion_gateway.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';

AppRoute _currentRoute(WidgetTester tester) =>
    AppRouterScope.of(tester.element(find.byType(AppFlow))).currentRoute;

Future<int> _noCards() async => 0;

/// Answers the sign-up state when the test lets it.
class _SlowAccountCompletionGateway extends FakeAccountCompletionGateway {
  final answer = Completer<AccountCompletionStatus>();

  @override
  Future<AccountCompletionStatus> fetchStatus() => answer.future;
}

void main() {
  testWidgets('a login that comes back from the provider\'s page keeps the '
      'login screen busy while the app is entered', (tester) async {
    useTestViewport(tester);
    final gateway = FakeSocialAuthGateway(
      result: SocialAuthResult.redirectStarted,
    );
    addTearDown(gateway.close);
    final completion = _SlowAccountCompletionGateway();
    await tester.pumpWidget(
      App(
        socialAuthGateway: gateway,
        accountCompletionGateway: completion,
        cardCountLoader: _noCards,
      ),
    );
    await tester.pump();
    gateway.emit(SocialAuthSessionEvent.noSession);
    await tester.pumpAndSettle();

    // The press ends when the provider's page opens.
    final google = find.byKey(const ValueKey<String>('google-login-button'));
    await tester.tap(google);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Back in the app with a session: the account is being asked about.
    gateway.emit(SocialAuthSessionEvent.signedIn);
    await tester.pump();
    await tester.pump();
    expect(_currentRoute(tester), AppRoute.appLogin);
    expect(
      find.descendant(
        of: google,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('kakao-login-button')));
    await tester.pump();
    expect(gateway.requestedProviders, [SocialAuthProvider.google]);

    completion.answer.complete(readyAccountStatus);
    await tester.pumpAndSettle();
    expect(_currentRoute(tester), AppRoute.home);
  });
}
