import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/core/analytics.dart';
import 'package:soolgyul/src/features/auth/data/social_auth_service.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';

// The app counts each screen as it comes to the front and the steps a
// visitor reaches, by name only.

class _Counted implements Analytics {
  final List<String> screens = <String>[];
  final List<String> events = <String>[];

  @override
  void screen(String name) => screens.add(name);

  @override
  void event(String name, [Map<String, Object> details = const {}]) =>
      events.add(details.isEmpty ? name : '$name $details');
}

AppRouter _router(WidgetTester tester) =>
    AppRouterScope.of(tester.element(find.byType(AppFlow)));

void main() {
  testWidgets('screens are counted once each, and a sign-in with its method', (
    tester,
  ) async {
    useTestViewport(tester);
    final counted = _Counted();
    final social = newAuthGateway();
    await tester.pumpWidget(
      App(
        analytics: counted,
        socialAuthGateway: social,
        accountCompletionGateway: FakeAccountCompletionGateway(
          status: readyAccountStatus,
        ),
        sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
      ),
    );
    await tester.pump();
    social.emit(SocialAuthSessionEvent.noSession);
    await tester.pumpAndSettle();
    expect(counted.screens, <String>['appLoading', 'appLogin']);
    expect(counted.events, isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('kakao-login-button')));
    await tester.pumpAndSettle();
    expect(_router(tester).currentRoute, AppRoute.home);
    expect(counted.screens.last, 'home');
    expect(counted.events, <String>['login {method: kakao}']);

    // The screen already in front is not counted again.
    final before = counted.screens.length;
    _router(tester).replaceRoot(AppRoute.home);
    await tester.pumpAndSettle();
    expect(counted.screens, hasLength(before));
  });
}
