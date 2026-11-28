import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/widgets/app_chip.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';
import 'package:soolgyul/src/widgets/app_surface.dart';
import 'package:soolgyul/src/widgets/main_tab_title.dart';
import 'package:soolgyul/src/features/preferences/presentation/history/preference_history_screen.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/home/presentation/home_screens.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_gateway.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_wire_requests.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_result.dart';
import 'package:soolgyul/src/navigation/app_route.dart';

import '../support/app_test_harness.dart';
import '../support/provider_harness.dart';
import '../support/design_taste_card.dart';

Future<void> pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(411, 891);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: page),
    ),
  );
  // A page still loading shows a spinner, which never settles.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<({List<String> taps})> pumpHome(
  WidgetTester tester, {
  bool scanLabel = false,
}) async {
  final taps = <String>[];
  await pumpPage(
    tester,
    withProviders(
      child: HomeScreen(
        onOpenSoolgyulLetters: () => taps.add('letters'),
        onOpenTasteFit: () => taps.add('fit'),
        onStartRecord: () => taps.add('record'),
        onScanLabel: scanLabel ? () => taps.add('label') : null,
      ),
    ),
  );
  return (taps: taps);
}

void main() {
  group('HomeScreen', () {
    testWidgets('shows the fit search and the letters, and nothing else', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('고민 중인 술이 있나요?'), findsOneWidget);
      expect(find.text('나의 취향 조각'), findsOneWidget);
      expect(find.byType(AppPanel), findsNWidgets(2));
      expect(find.text('다음 한 잔 가이드'), findsNothing);
    });

    testWidgets('the 술결 logo stands at the top left, in line with the boxes, '
        'in place of a written title', (tester) async {
      await pumpHome(tester);

      final logo = find.byKey(const ValueKey<String>('home-logo'));
      final firstBox = find.byType(AppPanel).first;
      expect(logo, findsOneWidget);
      expect(tester.getTopLeft(logo).dx, tester.getTopLeft(firstBox).dx);
      expect(
        tester.getBottomLeft(logo).dy,
        lessThan(tester.getTopLeft(firstBox).dy),
      );
      expect(find.text('홈'), findsNothing);
      expect(find.byType(MainTabTitle), findsNothing);
    });

    testWidgets('기록하기 is a chip at the right end of the logo\'s line and '
        'starts a record; the logo and the boxes stand where they did', (
      tester,
    ) async {
      final result = await pumpHome(tester);
      final logo = find.byKey(const ValueKey<String>('home-logo'));
      final chip = find.byKey(const ValueKey<String>('home-record-chip'));
      final firstBox = find.byType(AppPanel).first;

      // The page's top room, the logo, then the same room down to the box.
      expect(tester.getTopLeft(logo).dy, AppSpacing.lg);
      expect(tester.getSize(logo).height, 24);
      expect(
        tester.getTopLeft(firstBox).dy,
        AppSpacing.lg + 24 + AppSpacing.lg,
      );

      expect(
        find.descendant(of: chip, matching: find.text('기록하기')),
        findsOneWidget,
      );
      expect(tester.widget<AppChip>(chip).leadingIcon, AppIconAsset.edit);
      expect(tester.getCenter(chip).dy, tester.getCenter(logo).dy);
      expect(tester.getRect(chip).right, tester.getRect(firstBox).right);
      expect(tester.getSize(chip).height, AppSizes.minimumTapTarget);
      expect(tester.getRect(chip).top, greaterThanOrEqualTo(0));
      expect(
        tester.getRect(chip).bottom,
        lessThanOrEqualTo(tester.getTopLeft(firstBox).dy),
      );

      await tester.tap(chip);
      expect(result.taps, <String>['record']);
    });

    testWidgets('a narrow phone with large text keeps the logo and 기록하기 on '
        'one line', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHome(tester);
      tester.view.physicalSize = const Size(360, 780);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      final logo = find.byKey(const ValueKey<String>('home-logo'));
      final chip = find.byKey(const ValueKey<String>('home-record-chip'));
      expect(tester.getRect(logo).right, lessThan(tester.getRect(chip).left));
      expect(tester.getCenter(chip).dy, tester.getCenter(logo).dy);
    });

    testWidgets('search entry opens the taste-fit search', (tester) async {
      final result = await pumpHome(tester);

      expect(find.text('고민 중인 술이 있나요?'), findsOneWidget);
      expect(find.text('술 이름이나 브랜드 검색'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('home-taste-fit-entry')),
      );
      await tester.pumpAndSettle();

      expect(result.taps, <String>['fit']);
      expect(
        find.byKey(const ValueKey<String>('home-taste-fit-label')),
        findsNothing,
      );
    });

    testWidgets('the camera button opens the label photo search', (
      tester,
    ) async {
      final result = await pumpHome(tester, scanLabel: true);

      expect(find.text('라벨 사진으로 찾기'), findsNothing);
      expect(find.bySemanticsLabel('라벨 사진으로 찾기'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('home-taste-fit-label')),
      );
      await tester.pumpAndSettle();

      expect(result.taps, <String>['label']);
    });
  });

  group('a saved card in the app', () {
    const resultId = '20000000-0000-4000-8000-000000000009';
    Future<_History> openHistoryRecord(
      WidgetTester tester,
      _Cards cards,
    ) async {
      final history = _History(resultId);
      await pumpAppAtRoute(
        tester,
        AppRoute.preference,
        defaultAppTestViewport,
        null,
        null,
        cards,
        null,
        null,
        null,
        history,
      );
      final record = find.byKey(ValueKey<String>('history-record-$resultId'));
      await tester.ensureVisible(record);
      await tester.pumpAndSettle();
      await tester.tap(record);
      await tester.pumpAndSettle();
      return history;
    }

    Future<void> answerDelete(WidgetTester tester, {required bool yes}) async {
      await tester.tap(find.byKey(const ValueKey<String>('taste-card-more')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('taste-card-menu-delete')),
      );
      await tester.pumpAndSettle();
      expect(find.text('술결 기록을 삭제할까요?'), findsOneWidget);
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            yes ? 'record-delete-confirm' : 'record-delete-cancel',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a saved card is deleted only after the reader says yes', (
      tester,
    ) async {
      final cards = _Cards();
      final history = await openHistoryRecord(tester, cards);

      await answerDelete(tester, yes: false);
      expect(cards.deleted, isEmpty);
      expect(find.byType(TasteCardScreen), findsOneWidget);

      await answerDelete(tester, yes: true);
      expect(cards.deleted, [resultId]);
      expect(find.byType(TasteCardScreen), findsNothing);
      expect(find.text('기록을 삭제했어요.'), findsOneWidget);
      expect(history.loads, 2, reason: 'the list reloads without the record');
    });

    testWidgets('삭제 shows it is working and takes one tap only', (
      tester,
    ) async {
      final cards = _Cards()..deleteGate = Completer<void>();
      await openHistoryRecord(tester, cards);
      await tester.tap(find.byKey(const ValueKey<String>('taste-card-more')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('taste-card-menu-delete')),
      );
      await tester.pumpAndSettle();
      const confirm = ValueKey<String>('record-delete-confirm');

      await tester.tap(find.byKey(confirm));
      await tester.pump();

      // The sheet stays up with the button busy while the server works.
      expect(find.text('술결 기록을 삭제할까요?'), findsOneWidget);
      expect(tester.widget<AppButton>(find.byKey(confirm)).isLoading, isTrue);
      await tester.tap(find.byKey(confirm), warnIfMissed: false);
      await tester.pump();
      expect(cards.deleted, [resultId]);

      cards.deleteGate!.complete();
      await tester.pumpAndSettle();
      expect(cards.deleted, [resultId]);
      expect(find.text('술결 기록을 삭제할까요?'), findsNothing);
      expect(find.byType(TasteCardScreen), findsNothing);
      expect(find.byType(PreferenceHistoryScreen), findsOneWidget);
      expect(find.text('기록을 삭제했어요.'), findsOneWidget);
    });

    testWidgets(
      'a 취향 record opens its card, and deleting it reloads the list',
      (tester) async {
        final cards = _Cards();
        final history = _History(resultId);
        await pumpAppAtRoute(
          tester,
          AppRoute.preference,
          defaultAppTestViewport,
          null,
          null,
          cards,
          null,
          null,
          null,
          history,
        );
        final record = find.byKey(ValueKey<String>('history-record-$resultId'));
        await tester.ensureVisible(record);
        await tester.pumpAndSettle();
        await tester.tap(record);
        await tester.pumpAndSettle();
        expect(cards.fetched, [resultId]);
        expect(find.byType(TasteCardScreen), findsOneWidget);

        await answerDelete(tester, yes: true);
        expect(cards.deleted, [resultId]);
        expect(find.byType(TasteCardScreen), findsNothing);
        expect(find.byType(PreferenceHistoryScreen), findsOneWidget);
        expect(history.loads, 2, reason: 'the list reloads without the record');
        expect(
          find.byKey(ValueKey<String>('history-record-$resultId')),
          findsNothing,
        );
      },
    );

    testWidgets('a reopened card closes back where it came from', (
      tester,
    ) async {
      await openHistoryRecord(tester, _Cards());
      expect(find.byType(TasteCardScreen), findsOneWidget);
      expect(find.text('홈으로'), findsNothing);

      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      expect(find.byType(TasteCardScreen), findsNothing);
      expect(find.byType(PreferenceHistoryScreen), findsOneWidget);
    });

    testWidgets('a card that fails to open says so, not that making failed', (
      tester,
    ) async {
      await openHistoryRecord(tester, _Cards(fail: true));
      expect(find.text('술결 카드를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('술결 카드를 완성하지 못했어요'), findsNothing);
      expect(find.byTooltip('이전 화면으로 이동'), findsOneWidget);
    });

    testWidgets('a refused delete keeps the card on screen', (tester) async {
      final cards = _Cards(failDelete: true);
      await openHistoryRecord(tester, cards);

      await answerDelete(tester, yes: true);
      expect(cards.deleted, [resultId]);
      expect(find.byType(TasteCardScreen), findsOneWidget);
      expect(find.text('기록을 삭제하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('a history record opens the saved card it came from', (
      tester,
    ) async {
      final cards = _Cards();
      await openHistoryRecord(tester, cards);

      expect(cards.fetched, [resultId]);
      final screen = tester.widget<TasteCardScreen>(
        find.byType(TasteCardScreen),
      );
      expect(screen.viewData.snapshotRef, designTasteCard.snapshotRef);
    });

    testWidgets('a card that fails to load shows the retry state', (
      tester,
    ) async {
      final cards = _Cards(fail: true);
      await openHistoryRecord(tester, cards);

      expect(find.text('술결 카드를 불러오지 못했어요'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(cards.fetched, [resultId, resultId]);
    });
  });
}

class _Cards implements TasteCardGateway {
  _Cards({this.fail = false, this.failDelete = false});
  final bool fail;
  final bool failDelete;
  final fetched = <String>[];
  final deleted = <String>[];

  /// When set, a delete does not finish until this does.
  Completer<void>? deleteGate;

  @override
  Future<void> deleteOwnedResult(String resultId) async {
    deleted.add(resultId);
    await deleteGate?.future;
    if (failDelete) {
      throw const TasteCardGatewayException(TasteCardGatewayOperation.delete);
    }
  }

  @override
  bool get isAuthenticated => true;

  @override
  Future<TasteCardCreateOutcome> create(CreateTasteCardResultRequest r) =>
      throw UnimplementedError();

  @override
  Future<TasteCardResult> convert(AnonymousTasteCardConversionRequest r) =>
      throw UnimplementedError();

  @override
  Future<TasteCardResult> fetchOwnedResult(String resultId) async {
    fetched.add(resultId);
    if (fail) {
      throw const TasteCardGatewayException(TasteCardGatewayOperation.detail);
    }
    final viewData = designTasteCard;
    return TasteCardResult(
      resultId: resultId,
      recordId: '30000000-0000-4000-8000-000000000009',
      snapshotRef: viewData.snapshotRef,
      ownership: TasteCardOwnership.saved,
      viewData: viewData,
    );
  }
}

/// One record this month until it is deleted.
class _History implements PreferenceHistoryGateway {
  _History(this.resultId);
  final String resultId;
  int loads = 0;

  @override
  Future<DateTime?> latestRecordedAt() async => null;

  @override
  Future<List<HistoryRecord>> loadAll() async => const <HistoryRecord>[];

  @override
  Future<List<HistoryRecord>> loadMonth(DateTime month) async {
    loads++;
    if (loads > 1) return const <HistoryRecord>[];
    final now = DateTime.now();
    return [
      HistoryRecord(
        resultId: resultId,
        title: '샤토 테스트',
        categoryKey: 'wine',
        categoryLabel: '와인',
        recordedAt: DateTime(now.year, now.month, now.day, 12),
      ),
    ];
  }
}
