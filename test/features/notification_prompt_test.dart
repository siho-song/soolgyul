import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soolgyul/src/app/flows/app_gateways.dart';
import 'package:soolgyul/src/app/flows/flow_host.dart';
import 'package:soolgyul/src/app/flows/notification_prompt_coordinator.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/notifications/data/notification_access.dart';
import 'package:soolgyul/src/features/notifications/data/notification_prompt_memory.dart';
import 'package:soolgyul/src/features/notifications/presentation/notification_prompt_sheet.dart';
import 'package:soolgyul/src/features/notifications/presentation/widgets/notification_setting_row.dart';
import 'package:soolgyul/src/features/onboarding/data/sensory_questionnaire_data.dart';
import 'package:soolgyul/src/features/profile/data/marketing_consent_gateway.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';
import 'package:soolgyul/src/widgets/app_switch.dart';

class _Memory implements NotificationPromptMemory {
  NotificationPromptRecord? record = const NotificationPromptRecord();
  bool turnedOff = false;

  @override
  Future<NotificationPromptRecord?> read() async => record;

  @override
  Future<void> rememberAsked(DateTime at) async {
    record = NotificationPromptRecord(
      asks: (record?.asks ?? 0) + 1,
      lastAsked: at,
    );
  }

  @override
  Future<void> rememberTurnedOff() async => turnedOff = true;
}

class _Access extends PretendNotificationAccess {
  _Access({super.status});

  /// What the phone answers when it is asked.
  NotificationStatus? phoneAnswer;
  int settingsOpened = 0;

  @override
  Future<NotificationStatus> turnOn() async =>
      status = phoneAnswer ?? NotificationStatus.on;

  @override
  Future<void> openPhoneSettings() async => settingsOpened++;
}

class _Consent implements MarketingConsentGateway {
  bool value = false;
  bool fail = false;

  @override
  Future<bool> load() async => value;

  @override
  Future<bool> save(bool accepted) async {
    if (fail) throw StateError('offline');
    return value = accepted;
  }
}

class _Host implements FlowHost {
  _Host(this.router);

  @override
  final AppRouter router;
  final feedback = <String>[];

  @override
  bool get mounted => router.navigatorKey.currentContext != null;

  @override
  BuildContext get context => router.navigatorKey.currentContext!;

  @override
  void refresh(VoidCallback update) => update();

  @override
  void showFeedback(String message, {bool success = false}) =>
      feedback.add(message);

  @override
  void back() => router.pop();
}

void main() {
  final monday = DateTime(2026, 11, 9, 19);

  group('whether a member may be asked', () {
    bool ask({
      NotificationStatus status = NotificationStatus.off,
      int asks = 0,
      DateTime? lastAsked,
    }) => mayAskForNotifications(
      status: status,
      record: NotificationPromptRecord(asks: asks, lastAsked: lastAsked),
      now: monday,
    );

    test('asks a member whose notifications are off and never asked', () {
      expect(ask(), isTrue);
    });

    test('never asks when they are on or the phone refuses them', () {
      expect(ask(status: NotificationStatus.on), isFalse);
      expect(ask(status: NotificationStatus.blocked), isFalse);
    });

    test('waits a week after "not now", then asks once more only', () {
      final sixDaysAgo = monday.subtract(const Duration(days: 6));
      final sevenDaysAgo = monday.subtract(const Duration(days: 7));
      expect(ask(asks: 1, lastAsked: sixDaysAgo), isFalse);
      expect(ask(asks: 1, lastAsked: sevenDaysAgo), isTrue);
      expect(ask(asks: 2, lastAsked: sevenDaysAgo), isFalse);
    });
  });

  group('the moment to ask', () {
    bool moment(AppRoute? previous, AppRoute current, {bool card = false}) =>
        isNotificationPromptMoment(
          previous: previous,
          current: current,
          newRepeatCard: card,
        );

    test('back from a bottle\'s fit to the search', () {
      expect(moment(AppRoute.tasteFitDetail, AppRoute.tasteFitSearch), isTrue);
    });

    test('not when the fit page leads on to a record', () {
      expect(
        moment(AppRoute.tasteFitDetail, AppRoute.recordQuestions),
        isFalse,
      );
    });

    test('leaving a newly saved card that is not the first', () {
      expect(
        moment(AppRoute.onboardingResult, AppRoute.home, card: true),
        isTrue,
      );
      expect(moment(AppRoute.onboardingResult, AppRoute.home), isFalse);
    });

    test('not on any other change of page', () {
      expect(
        moment(AppRoute.home, AppRoute.tasteFitSearch, card: true),
        isFalse,
      );
      expect(moment(null, AppRoute.home), isFalse);
    });
  });

  group('what the phone remembers', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('counts the asks of each account apart', () async {
      String? account = 'a';
      final memory = DeviceNotificationPromptMemory(accountId: () => account);
      await memory.rememberAsked(monday);
      expect((await memory.read())!.asks, 1);
      expect((await memory.read())!.lastAsked, monday);

      account = 'b';
      expect((await memory.read())!.asks, 0);
      expect((await memory.read())!.lastAsked, isNull);
    });

    test('a member who turned them off by hand is not asked again', () async {
      final memory = DeviceNotificationPromptMemory(accountId: () => 'a');
      await memory.rememberTurnedOff();
      expect((await memory.read())!.asks, notificationPromptMaxAsks);
    });

    test('remembers nothing while nobody is signed in', () async {
      final memory = DeviceNotificationPromptMemory(accountId: () => null);
      await memory.rememberAsked(monday);
      expect(await memory.read(), isNull);
    });
  });

  group('asking', () {
    late AppRouter router;
    late _Host host;
    late _Memory memory;
    late _Access access;
    late _Consent consent;
    late NotificationPromptCoordinator coordinator;
    late Future<void> Function() pagesSettled;

    Future<void> pump(WidgetTester tester, {bool isWeb = false}) async {
      router = AppRouter(
        initialRoute: AppRoute.tasteFitSearch,
        child: const SizedBox(),
      );
      host = _Host(router);
      memory = _Memory();
      pagesSettled = () async {};
      access = _Access();
      consent = _Consent();
      coordinator = NotificationPromptCoordinator(
        host,
        AppGateways(
          sensoryQuestionnaireLoader: loadSensoryQuestionnaireData,
          isWeb: isWeb,
          marketingConsent: consent,
          notifications: access,
          notificationPromptMemory: memory,
        ),
        now: () => monday,
        pagesSettled: () => pagesSettled(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          navigatorKey: router.navigatorKey,
          home: const Scaffold(),
        ),
      );
    }

    Future<void> offer(WidgetTester tester) async {
      final done = coordinator.offer();
      await tester.pumpAndSettle();
      return done;
    }

    testWidgets('"맞춤 알림 받기" turns them on and agrees to marketing', (
      tester,
    ) async {
      await pump(tester);
      final done = coordinator.offer();
      await tester.pumpAndSettle();
      expect(find.text('오늘 마실 술,\n실패 없이 고르고 싶을 때'), findsOneWidget);
      expect(find.text('혜택 및 추천 알림 수신에 동의해요'), findsOneWidget);

      await tester.tap(find.text('맞춤 알림 받기'));
      await tester.pumpAndSettle();
      await done;

      expect(access.status, NotificationStatus.on);
      expect(consent.value, isTrue);
      expect(memory.record!.asks, 0);
      expect(host.feedback, <String>['맞춤 알림을 켰어요.']);
    });

    testWidgets('"다음에 할게요" changes nothing and counts as one ask', (
      tester,
    ) async {
      await pump(tester);
      final done = coordinator.offer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('다음에 할게요'));
      await tester.pumpAndSettle();
      await done;

      expect(access.status, NotificationStatus.off);
      expect(consent.value, isFalse);
      expect(memory.record!.asks, 1);
      expect(memory.record!.lastAsked, monday);
    });

    testWidgets('a refusal on the phone leaves the marketing agreement off', (
      tester,
    ) async {
      await pump(tester);
      access.phoneAnswer = NotificationStatus.blocked;
      final done = coordinator.offer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('맞춤 알림 받기'));
      await tester.pumpAndSettle();
      await done;

      expect(consent.value, isFalse);
      expect(memory.record!.asks, 1);
      expect(host.feedback, isEmpty);
    });

    testWidgets('says so when the agreement could not be saved', (
      tester,
    ) async {
      await pump(tester);
      consent.fail = true;
      final done = coordinator.offer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('맞춤 알림 받기'));
      await tester.pumpAndSettle();
      await done;

      expect(access.status, NotificationStatus.on);
      expect(host.feedback.single, contains('수신 동의를 저장하지 못했어요'));
    });

    testWidgets('gives up on a page that never comes to rest, and asks at '
        'the next moment', (tester) async {
      await pump(tester);
      pagesSettled = () => Completer<void>().future;
      final stuck = coordinator.offer();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await stuck;
      expect(find.byType(NotificationPromptSheet), findsNothing);
      expect(memory.record!.asks, 0);

      pagesSettled = () async {};
      final done = coordinator.offer();
      await tester.pumpAndSettle();
      expect(find.byType(NotificationPromptSheet), findsOneWidget);
      await tester.tap(find.text('다음에 할게요'));
      await tester.pumpAndSettle();
      await done;
    });

    testWidgets('shows nothing to a member already asked twice', (
      tester,
    ) async {
      await pump(tester);
      memory.record = const NotificationPromptRecord(asks: 2);
      await offer(tester);
      expect(find.byType(NotificationPromptSheet), findsNothing);
    });

    testWidgets('shows nothing on the web or while signed out', (tester) async {
      await pump(tester, isWeb: true);
      await offer(tester);
      expect(find.byType(NotificationPromptSheet), findsNothing);

      await pump(tester);
      memory.record = null;
      await offer(tester);
      expect(find.byType(NotificationPromptSheet), findsNothing);
    });
  });

  group('the settings row', () {
    Future<void> pumpRow(
      WidgetTester tester,
      _Access access, [
      _Memory? memory,
    ]) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: NotificationSettingRow(access: access, memory: memory),
        ),
      ),
    );

    bool switchValue(WidgetTester tester) =>
        tester.widget<AppSwitch>(find.byType(AppSwitch)).value;

    testWidgets('turns notifications on and off', (tester) async {
      final access = _Access();
      final memory = _Memory();
      await pumpRow(tester, access, memory);
      await tester.pumpAndSettle();
      expect(switchValue(tester), isFalse);

      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();
      expect(access.status, NotificationStatus.on);
      expect(switchValue(tester), isTrue);
      expect(memory.turnedOff, isFalse);

      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();
      expect(access.status, NotificationStatus.off);
      expect(memory.turnedOff, isTrue);
    });

    testWidgets('offers the phone\'s settings when the phone refuses them, '
        'and reads the state again on coming back', (tester) async {
      final access = _Access(status: NotificationStatus.blocked);
      await pumpRow(tester, access);
      await tester.pumpAndSettle();
      expect(find.byType(AppSwitch), findsNothing);
      expect(find.text('폰 설정에서 술결 알림이 꺼져 있어요'), findsOneWidget);

      await tester.tap(find.text('설정 열기'));
      await tester.pump();
      expect(access.settingsOpened, 1);

      access.status = NotificationStatus.off;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('설정 열기'), findsNothing);
      expect(switchValue(tester), isFalse);
    });
  });
}
