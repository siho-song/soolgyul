import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/profile/presentation/account_deleting_dialog.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';
import 'package:soolgyul/src/widgets/app_dialog.dart';
import 'package:soolgyul/src/widgets/app_sheet.dart';
import 'package:soolgyul/src/widgets/app_term_tooltip.dart';

import '../support/app_test_harness.dart';

AppRouter _router(WidgetTester tester) =>
    AppRouterScope.of(tester.element(find.byType(AppFlow)));

/// The Android back button or gesture; whether the app took it. Left
/// untaken, the phone closes the app.
Future<bool> _systemBack(WidgetTester tester) async {
  final taken = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return taken;
}

/// 약관 및 정책 opened from 마이페이지, so there is a page to go back to.
Future<AppRouter> _openPolicy(WidgetTester tester) async {
  await pumpAppAtRoute(tester, AppRoute.profile);
  final router = _router(tester)..push(AppRoute.policy);
  await tester.pumpAndSettle();
  return router;
}

const _policyOverProfile = <AppRoute>[AppRoute.profile, AppRoute.policy];

void main() {
  testWidgets('system back closes an open sheet and keeps the page', (
    tester,
  ) async {
    final router = await _openPolicy(tester);
    final withdrawal = find.byKey(
      const ValueKey<String>('policy-account-deletion'),
    );
    await tester.ensureVisible(withdrawal);
    await tester.tap(withdrawal);
    await tester.pumpAndSettle();
    expect(find.text('정말 탈퇴하시겠어요?'), findsOneWidget);

    expect(await _systemBack(tester), isTrue);
    expect(find.text('정말 탈퇴하시겠어요?'), findsNothing);
    expect(router.stack, _policyOverProfile);
    expect(find.text('계정 관리'), findsOneWidget);
  });

  testWidgets('on a tab, system back closes the sheet instead of the app', (
    tester,
  ) async {
    await pumpAppAtRoute(tester, AppRoute.home);
    final router = _router(tester);
    showAppSheet<void>(
      context: router.navigatorKey.currentContext!,
      builder: (_) => const AppSheetBody(
        title: '시트',
        body: '탭 화면 위에 열린 시트',
        children: <Widget>[],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('시트'), findsOneWidget);

    expect(await _systemBack(tester), isTrue);
    expect(find.text('시트'), findsNothing);
    expect(router.currentRoute, AppRoute.home);

    // With nothing open the tab has nowhere to go back to, as before.
    expect(await _systemBack(tester), isFalse);
    expect(router.currentRoute, AppRoute.home);
  });

  testWidgets('system back leaves a popup that must be answered up', (
    tester,
  ) async {
    final router = await _openPolicy(tester);
    showAppDialog<void>(
      context: router.navigatorKey.currentContext!,
      dismissible: false,
      builder: (_) => const AccountDeletingDialog(),
    );
    await tester.pumpAndSettle();
    expect(find.text('계정을 삭제하고 있어요'), findsOneWidget);

    expect(await _systemBack(tester), isTrue);
    expect(find.text('계정을 삭제하고 있어요'), findsOneWidget);
    expect(router.stack, _policyOverProfile);

    await tester.tap(find.byKey(const ValueKey('account-deleting-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('계정을 삭제하고 있어요'), findsNothing);
    expect(router.stack, _policyOverProfile);
  });

  testWidgets('system back closes a dropdown list and keeps what was typed', (
    tester,
  ) async {
    await pumpAppAtRoute(tester, AppRoute.supportCenter);
    final router = _router(tester)..push(AppRoute.supportInquiry);
    await tester.pumpAndSettle();
    final email = find.descendant(
      of: find.byKey(const ValueKey<String>('support-inquiry-email')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(email, 'user@example.com');
    await tester.tap(
      find.byKey(const ValueKey<String>('support-inquiry-type')),
    );
    await tester.pumpAndSettle();
    expect(find.text('기타 문의'), findsOneWidget);

    expect(await _systemBack(tester), isTrue);
    expect(find.text('기타 문의'), findsNothing);
    expect(router.currentRoute, AppRoute.supportInquiry);
    expect(
      tester.widget<EditableText>(email).controller.text,
      'user@example.com',
    );
  });

  testWidgets('system back closes a balloon before the page under it', (
    tester,
  ) async {
    final router = await _openPolicy(tester);
    showTermTooltip(
      tester.element(find.text('계정 관리')),
      title: '용어',
      text: '설명',
    );
    await tester.pumpAndSettle();
    expect(find.byType(TermTooltipLayer), findsOneWidget);

    expect(await _systemBack(tester), isTrue);
    expect(find.byType(TermTooltipLayer), findsNothing);
    expect(router.stack, _policyOverProfile);
  });

  testWidgets('with nothing open, system back leaves the page as before', (
    tester,
  ) async {
    final router = await _openPolicy(tester);
    expect(router.stack, _policyOverProfile);

    expect(await _systemBack(tester), isTrue);
    expect(router.stack, <AppRoute>[AppRoute.profile]);
    expect(find.text('계정 관리'), findsNothing);
  });
}
