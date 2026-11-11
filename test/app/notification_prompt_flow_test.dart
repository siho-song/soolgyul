import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/features/notifications/data/notification_access.dart';
import 'package:soolgyul/src/features/notifications/data/notification_prompt_memory.dart';
import 'package:soolgyul/src/features/notifications/presentation/notification_prompt_sheet.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';
import '../support/design_taste_card.dart';
import '../support/test_catalog.dart';

class _Memory implements NotificationPromptMemory {
  NotificationPromptRecord record = const NotificationPromptRecord();

  @override
  Future<NotificationPromptRecord?> read() async => record;

  @override
  Future<void> rememberAsked(DateTime at) async {
    record = NotificationPromptRecord(asks: record.asks + 1, lastAsked: at);
  }

  @override
  Future<void> rememberTurnedOff() async {}
}

class _SavingCards implements TasteCardGateway {
  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardCreateOutcome> create(
    CreateTasteCardResultRequest request,
  ) async => TasteCardFinalOutcome(
    TasteCardResult(
      resultId: '20000000-0000-4000-8000-000000000001',
      recordId: '30000000-0000-4000-8000-000000000001',
      snapshotRef: designTasteCard.snapshotRef,
      ownership: TasteCardOwnership.saved,
      viewData: designTasteCard,
    ),
  );

  @override
  Future<TasteCardResult> convert(
    AnonymousTasteCardConversionRequest request,
  ) => throw UnimplementedError();

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteOwnedResult(String resultId) => throw UnimplementedError();
}

Future<void> _pumpApp(
  WidgetTester tester,
  AppRoute route, {
  NotificationAccess? access,
  NotificationPromptMemory? memory,
  TasteCardGateway? cards,
}) async {
  tester.view.physicalSize = defaultAppTestViewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const channel = MethodChannel('soolgyul/debug-screen');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) async => route.debugScreen,
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  await tester.pumpWidget(
    App(
      catalogSearchGateway: const TestCatalogGateway(),
      tasteCardGateway: cards,
      sensoryQuestionnaireLoader: loadTestSensoryQuestionnaire,
      notificationAccess: access,
      notificationPromptMemory: memory,
    ),
  );
  await tester.pumpAndSettle();
}

/// The system back, then the time the page takes to move away.
Future<void> _leave(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  for (var i = 0; i < 3; i++) {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens a bottle's fit page over the search, as picking a bottle does.
Future<void> _openFitDetail(WidgetTester tester) async {
  AppRouterScope.of(
    tester.element(find.byType(AppFlow)),
  ).push(AppRoute.tasteFitDetail);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('back from a bottle\'s fit asks about notifications, once', (
    tester,
  ) async {
    final memory = _Memory();
    await _pumpApp(
      tester,
      AppRoute.tasteFitSearch,
      access: PretendNotificationAccess(),
      memory: memory,
    );
    await _openFitDetail(tester);
    expect(find.byType(NotificationPromptSheet), findsNothing);

    await _leave(tester);
    expect(find.byType(NotificationPromptSheet), findsOneWidget);

    await tester.tap(find.text('다음에 할게요'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationPromptSheet), findsNothing);
    expect(memory.record.asks, 1);

    // A week has not passed: the next bottle does not ask again.
    await _openFitDetail(tester);
    await _leave(tester);
    expect(find.byType(NotificationPromptSheet), findsNothing);
  });

  testWidgets('nobody is asked while no phone is connected', (tester) async {
    await _pumpApp(tester, AppRoute.tasteFitSearch, memory: _Memory());
    await _openFitDetail(tester);
    await _leave(tester);
    expect(find.byType(NotificationPromptSheet), findsNothing);
  });

  testWidgets('leaving a newly saved card that is not the first asks', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      AppRoute.home,
      access: PretendNotificationAccess(),
      memory: _Memory(),
      cards: _SavingCards(),
    );
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '테스트 드라이');
    await pumpCatalogSearch(tester);
    await tester.tap(find.text('테스트 드라이 화이트 와인'));
    await tester.pump();
    await tester.ensureVisible(find.text('다음'));
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tapSensoryOption(tester, 'revisit:wantAgain');
    await tapSensoryOption(tester, 'sensory-next');
    await tapSensoryOption(tester, 'aroma:unsure');
    await tapSensoryOption(tester, 'reaction:taste:sweetness:liked');
    await tapSensoryOption(tester, 'reason:taste:sweetness:gentle');
    await answerAllTastesFine(tester, except: {'sweetness'});
    await tapSensoryOption(tester, 'mouthfeel:unsure');
    await tapSensoryOption(tester, 'finish:aromaEcho');
    await tapSensoryOption(tester, 'sensory-next');
    expect(find.byType(TasteCardScreen), findsOneWidget);
    expect(find.byType(NotificationPromptSheet), findsNothing);

    await _leave(tester);
    expect(find.byType(TasteCardScreen), findsNothing);
    expect(find.byType(NotificationPromptSheet), findsOneWidget);
  });
}
