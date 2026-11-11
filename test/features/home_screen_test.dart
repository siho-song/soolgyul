import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/widgets/app_button.dart';
import 'package:soolgyul/src/features/preferences/presentation/history/preference_history_screen.dart';
import 'package:soolgyul/src/features/preferences/data/preference_history_content.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/home/data/next_drink_guides.dart';
import 'package:soolgyul/src/features/home/presentation/home_screens.dart';
import 'package:soolgyul/src/features/taste_card/presentation/taste_card_screen.dart';
import 'package:soolgyul/src/features/taste_card/data/taste_card_snapshot_view_data.dart';
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

class _GuidesGateway implements NextDrinkGuidesGateway {
  _GuidesGateway(this.guides);
  final List<NextDrinkGuide> guides;
  final completer = Completer<List<NextDrinkGuide>>();

  @override
  Future<List<NextDrinkGuide>> load() => completer.future;
}

NextDrinkGuide guideOf(
  String id,
  String kind, {
  List<String> picks = const [],
  String category = '와인',
}) => NextDrinkGuide(
  resultId: id,
  kindLabel: kind,
  categoryLabel: category,
  guide: TasteCardGuideViewData(
    head: '머리 문장',
    levels: const [
      TasteCardGuideLevelViewData(label: '당도', mark: 1, range: '1~2'),
      TasteCardGuideLevelViewData(label: '산도', mark: 4, range: '4'),
    ],
    picks: [
      for (final pick in picks)
        TasteCardGuidePickViewData(country: 'it', place: '이탈리아', keyword: pick),
    ],
  ),
);

final sampleGuides = <NextDrinkGuide>[
  guideOf('result-1', '레드 와인', picks: ['바르베라', '코르비나']),
  guideOf('result-2', '싱글몰트 위스키', picks: ['셰리 캐스크']),
  guideOf('result-3', '준마이 긴조'),
];

Future<({List<String> opened, List<String> taps})> pumpHome(
  WidgetTester tester, {
  bool scanLabel = false,
  NextDrinkGuidesGateway? guides,
}) async {
  final opened = <String>[];
  final taps = <String>[];
  await pumpPage(
    tester,
    withProviders(
      guides: guides,
      child: HomeScreen(
        onOpenSoolgyulLetters: () => taps.add('letters'),
        onOpenCard: opened.add,
        onOpenTasteFit: () => taps.add('fit'),
        onScanLabel: scanLabel ? () => taps.add('label') : null,
      ),
    ),
  );
  return (opened: opened, taps: taps);
}

Finder get carousel => find.byKey(const Key('next-drink-carousel'));

void main() {
  group('HomeScreen', () {
    testWidgets('renders every section', (tester) async {
      await pumpHome(tester, guides: _OneGuide('result-one'));
      await tester.pump();

      expect(find.text('고민 중인 술이 있나요?'), findsOneWidget);
      expect(find.text('나의 취향 조각'), findsOneWidget);
      expect(find.text(NextDrinkGuideCard.title), findsOneWidget);
      expect(find.text('다음에 음용하실 레드 와인은 아래의 기준에 맞게 찾아보세요'), findsWidgets);
      expect(find.text('바르베라'), findsWidgets);
      expect(find.text('다음 한 잔을 위해'), findsNothing);
    });

    testWidgets('without a gateway the guide card has nothing to show', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text(NextDrinkGuideCard.emptyMessage), findsOneWidget);
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

    testWidgets('a whisky kind named without the word is given it', (
      tester,
    ) async {
      final guides = [guideOf('result-1', '버번', category: '위스키')];
      final gateway = _GuidesGateway(guides);
      await pumpHome(tester, guides: gateway);
      gateway.completer.complete(guides);
      await tester.pumpAndSettle();

      expect(find.text('다음에 음용하실 버번 위스키는 아래의 기준에 맞게 찾아보세요'), findsOneWidget);
    });

    testWidgets('guide card shows loading, then one slide per recent card', (
      tester,
    ) async {
      final gateway = _GuidesGateway(sampleGuides);
      final result = await pumpHome(tester, guides: gateway);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      gateway.completer.complete(sampleGuides);
      await tester.pumpAndSettle();

      // The offstage copies that measure each slide are hidden from finders,
      // so only the page view's own page shows.
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('다음에 음용하실 레드 와인은 아래의 기준에 맞게 찾아보세요'), findsOneWidget);
      expect(find.text('당도'), findsOneWidget);
      expect(find.text('산도'), findsOneWidget);
      expect(find.text('바르베라'), findsOneWidget);
      expect(find.text('코르비나'), findsOneWidget);
      expect(find.text('다음에 음용하실 싱글몰트 위스키는 아래의 기준에 맞게 찾아보세요'), findsNothing);
      final firstHeight = tester.getSize(carousel).height;
      // The guide's prose stays on the card; the home shows only the figure.
      expect(find.text('머리 문장'), findsNothing);

      await tester.drag(carousel, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('다음에 음용하실 싱글몰트 위스키는 아래의 기준에 맞게 찾아보세요'), findsOneWidget);
      expect(find.text('셰리 캐스크'), findsOneWidget);
      // The pager takes the shown slide's own height, not the tallest one.
      expect(tester.getSize(carousel).height, isNot(firstHeight));

      await tester.tap(find.byKey(const ValueKey('next-drink-guide:result-2')));
      await tester.pumpAndSettle();
      expect(result.opened, ['result-2']);

      await tester.drag(carousel, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('다음에 음용하실 준마이 긴조는 아래의 기준에 맞게 찾아보세요'), findsOneWidget);
    });

    testWidgets('a taller slide coming in under the finger is not cut off', (
      tester,
    ) async {
      final guides = [
        guideOf('result-1', '준마이 긴조'),
        guideOf('result-2', '레드 와인', picks: ['바르베라', '코르비나']),
      ];
      final gateway = _GuidesGateway(guides);
      await pumpHome(tester, guides: gateway);
      gateway.completer.complete(guides);
      await tester.pumpAndSettle();
      final shortHeight = tester.getSize(carousel).height;

      final gesture = await tester.startGesture(tester.getCenter(carousel));
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final midHeight = tester.getSize(carousel).height;

      await gesture.moveBy(const Offset(-200, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      final tallHeight = tester.getSize(carousel).height;
      expect(tallHeight, greaterThan(shortHeight));
      // The pager grows with the swipe, so it is between the two on the way.
      expect(midHeight, greaterThan(shortHeight));
      expect(midHeight, lessThan(tallHeight));
    });

    testWidgets(
      'guide card says when there is no guide yet or loading failed',
      (tester) async {
        final empty = _GuidesGateway(const []);
        await pumpHome(tester, guides: empty);
        empty.completer.complete(const []);
        await tester.pumpAndSettle();
        expect(find.text(NextDrinkGuideCard.emptyMessage), findsOneWidget);
        expect(carousel, findsNothing);

        // A fresh start whose first read fails (a refresh that fails keeps
        // the guides already shown).
        await tester.pumpWidget(const SizedBox());
        final failing = _GuidesGateway(const []);
        await pumpHome(tester, guides: failing);
        failing.completer.completeError(StateError('no network'));
        await tester.pumpAndSettle();
        expect(find.text(NextDrinkGuideCard.failureMessage), findsOneWidget);
      },
    );
  });

  group('SoolgyulLettersDetailScreen', () {
    testWidgets('renders its main sections without a survey', (tester) async {
      await pumpPage(
        tester,
        withProviders(child: const SoolgyulLettersDetailScreen()),
      );

      await tester.scrollUntilVisible(
        find.text('채워질 취향 조각'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('지금까지의 해석, 잘 맞나요?'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('next drink guide in the app', () {
    const resultId = '20000000-0000-4000-8000-000000000009';
    Future<void> pumpHomeRoute(
      WidgetTester tester,
      _Cards cards, [
      _OneGuide? guides,
    ]) => pumpAppAtRoute(
      tester,
      AppRoute.home,
      defaultAppTestViewport,
      null,
      null,
      cards,
      null,
      null,
      guides ?? _OneGuide(resultId),
    );

    Future<void> openCard(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey('next-drink-guide:$resultId')),
      );
      await tester.pumpAndSettle();
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
      final guides = _OneGuide(resultId);
      await pumpHomeRoute(tester, cards, guides);
      await openCard(tester);

      await answerDelete(tester, yes: false);
      expect(cards.deleted, isEmpty);
      expect(find.byType(TasteCardScreen), findsOneWidget);

      await answerDelete(tester, yes: true);
      expect(cards.deleted, [resultId]);
      expect(find.byType(TasteCardScreen), findsNothing);
      expect(find.text('기록을 삭제했어요.'), findsOneWidget);
      expect(guides.loads, 2, reason: 'home reloads without the record');
    });

    testWidgets('삭제 shows it is working and takes one tap only', (
      tester,
    ) async {
      final cards = _Cards()..deleteGate = Completer<void>();
      final guides = _OneGuide(resultId);
      await pumpHomeRoute(tester, cards, guides);
      await openCard(tester);
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
      expect(find.byType(HomeScreen), findsOneWidget);
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

    testWidgets('a reopened card has a way back and no 저장 button', (
      tester,
    ) async {
      await openHistoryRecord(tester, _Cards());
      expect(find.byType(TasteCardScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('save-preference-button')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('이전 화면으로 이동'));
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
      await pumpHomeRoute(tester, cards);
      await openCard(tester);

      await answerDelete(tester, yes: true);
      expect(cards.deleted, [resultId]);
      expect(find.byType(TasteCardScreen), findsOneWidget);
      expect(find.text('기록을 삭제하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('a guide slide opens the saved card it came from', (
      tester,
    ) async {
      final cards = _Cards();
      await pumpHomeRoute(tester, cards);
      expect(find.text(NextDrinkGuideCard.title), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('next-drink-guide:$resultId')),
      );
      await tester.pumpAndSettle();

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
      await pumpHomeRoute(tester, cards);

      await tester.tap(
        find.byKey(const ValueKey('next-drink-guide:$resultId')),
      );
      await tester.pumpAndSettle();

      expect(find.text('술결 카드를 불러오지 못했어요'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(cards.fetched, [resultId, resultId]);
    });
  });
}

class _OneGuide implements NextDrinkGuidesGateway {
  _OneGuide(this.resultId);
  final String resultId;
  int loads = 0;

  @override
  Future<List<NextDrinkGuide>> load() async {
    loads++;
    return [
      NextDrinkGuide(
        resultId: resultId,
        kindLabel: '레드 와인',
        categoryLabel: '와인',
        guide: designTasteCard.bite.guide!,
      ),
    ];
  }
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
