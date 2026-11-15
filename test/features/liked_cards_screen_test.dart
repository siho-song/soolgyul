import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/widgets/app_filter_chip.dart';
import 'package:soolgyul/src/widgets/app_icon.dart';
import 'package:soolgyul/src/widgets/app_icon_button.dart';
import 'package:soolgyul/src/widgets/app_state_view.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary_provider.dart';
import 'package:soolgyul/src/features/profile/data/liked_cards_gateway.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';

LikedCard card(String id, {String category = 'wine', String? note}) =>
    LikedCard(
      id: id,
      resultId: 'card-$id',
      title: '같은 이름',
      summary: '실제 요약 $id',
      note: note,
      category: category,
      recordedAt: DateTime(2026, 9, 21),
      likedAt: DateTime(2026, 9, 22),
    );

class FakeLikes implements LikedCardsGateway {
  @override
  Future<bool> isLiked(String cardId) async =>
      rows.any((row) => row.id == cardId);
  @override
  Future<void> like(String cardId, {DateTime? likedAt}) async {
    likes.add((cardId, likedAt));
    if (!await isLiked(cardId)) rows.insert(0, card(cardId));
  }

  final likes = <(String, DateTime?)>[];

  List<LikedCard> rows = [card('a'), card('b', category: 'whisky')];
  final removed = <String>[];
  final requests = <({String? category, bool latestFirst, int offset})>[];
  bool failLoad = false;
  bool failUnlike = false;
  Completer<void>? pendingUnlike;

  /// Holds every answer back until it completes.
  Completer<void>? pendingFetch;
  int pageSize = 30;

  @override
  Future<LikedCardsPage> fetch({
    String? category,
    bool latestFirst = true,
    int offset = 0,
  }) async {
    requests.add((
      category: category,
      latestFirst: latestFirst,
      offset: offset,
    ));
    if (pendingFetch case final pending?) await pending.future;
    if (failLoad) throw StateError('offline');
    var filtered = rows
        .where((row) => category == null || row.category == category)
        .toList();
    if (!latestFirst) filtered = filtered.reversed.toList();
    return LikedCardsPage(
      cards: filtered.skip(offset).take(pageSize).toList(),
      total: filtered.length,
    );
  }

  @override
  Future<void> unlike(String cardId) async {
    removed.add(cardId);
    if (pendingUnlike != null) await pendingUnlike!.future;
    if (failUnlike) throw StateError('offline');
    rows.removeWhere((row) => row.id == cardId);
  }
}

Future<void> pump(
  WidgetTester tester,
  LikedCardsGateway gateway, {
  ValueChanged<String>? onOpenCard,
}) async {
  tester.view.physicalSize = const Size(411, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SavedCardsScreen(gateway: gateway, onOpenCard: onOpenCard),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'app navigation connects list and refreshes profile count after unlike',
    (tester) async {
      final gateway = FakeLikes();
      var summaryLoads = 0;
      final router = AppRouter(
        initialRoute: AppRoute.profile,
        child: AppFlow(
          initialRoute: AppRoute.profile,
          likedCardsGateway: gateway,
        ),
      );
      Future<ProfileSummary> summary() async {
        summaryLoads++;
        return ProfileSummary(
          cardCount: 2,
          savedArticleCount: 0,
          likedCardCount: gateway.rows.length,
        );
      }

      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(411, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [profileSummaryLoaderProvider.overrideWithValue(summary)],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerDelegate: router,
            routeInformationParser: AppRouteInformationParser(
              fallback: AppRoute.profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('보관한 술결 카드'));
      await tester.pumpAndSettle();
      expect(router.currentRoute, AppRoute.savedCards);
      expect(find.text('총 2개'), findsOneWidget);
      await tester.tap(find.byTooltip('보관 취소').first);
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(router.currentRoute, AppRoute.profile);
      expect(summaryLoads, 2);
      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets('server list supports filters, sorting and ID-based unlike', (
    tester,
  ) async {
    final gateway = FakeLikes();
    await pump(tester, gateway);
    expect(find.text('총 2개'), findsOneWidget);
    expect(find.text('같은 이름'), findsNWidgets(2));
    await tester.tap(find.text('최신순'));
    await tester.pumpAndSettle();
    expect(gateway.requests.last.latestFirst, isFalse);
    await tester.tap(find.byTooltip('보관 취소').first);
    await tester.pumpAndSettle();
    expect(gateway.removed, ['b']);
    expect(find.text('실제 요약 a'), findsOneWidget);
    expect(find.text('실제 요약 b'), findsNothing);
    expect(find.text('총 1개'), findsOneWidget);
    await tester.tap(find.text('와인').first);
    await tester.pumpAndSettle();
    expect(gateway.requests.last.category, 'wine');
    await tester.tap(find.byTooltip('보관 취소'));
    await tester.pumpAndSettle();
    expect(find.text('총 0개'), findsOneWidget);
    expect(find.text('선택한 주종에 보관된 술결 카드가 없어요.'), findsOneWidget);
  });

  testWidgets(
    'unlike waits for server, prevents duplicate taps and retains failure',
    (tester) async {
      final gateway = FakeLikes()
        ..pendingUnlike = Completer<void>()
        ..failUnlike = true;
      await pump(tester, gateway);
      await tester.tap(find.byTooltip('보관 취소').first);
      await tester.pump();
      await tester.tap(find.byTooltip('보관 취소').first);
      expect(gateway.removed, ['a']);
      expect(find.text('실제 요약 a'), findsOneWidget);
      gateway.pendingUnlike!.complete();
      await tester.pumpAndSettle();
      expect(find.text('실제 요약 a'), findsOneWidget);
      expect(find.text('처리에 실패했어요. 다시 시도해 주세요.'), findsOneWidget);
      gateway.failUnlike = false;
      await tester.tap(find.byTooltip('보관 취소').first);
      await tester.pumpAndSettle();
      expect(find.text('실제 요약 a'), findsNothing);
    },
  );

  testWidgets('a card shows its line, opens the card and its note', (
    tester,
  ) async {
    final opened = <String>[];
    final gateway = FakeLikes()..rows = [card('a', note: '다시 마시고 싶어요')];
    await pump(tester, gateway, onOpenCard: opened.add);
    expect(find.text('실제 요약 a'), findsOneWidget);

    await tester.tap(find.text('같은 이름'));
    await tester.pumpAndSettle();
    expect(opened, ['card-a']);

    await tester.tap(find.byKey(const ValueKey<String>('liked-card-note-a')));
    await tester.pumpAndSettle();
    expect(find.text('다시 마시고 싶어요'), findsOneWidget);
    expect(opened, ['card-a'], reason: 'the note mark does not open the card');
  });

  testWidgets('an unlike can be undone and the card returns at its time', (
    tester,
  ) async {
    final gateway = FakeLikes();
    await pump(tester, gateway);
    await tester.tap(find.byTooltip('보관 취소').first);
    await tester.pumpAndSettle();
    expect(find.text('실제 요약 a'), findsNothing);
    expect(find.text('보관을 취소했어요.'), findsOneWidget);

    await tester.tap(find.text('실행 취소'));
    await tester.pumpAndSettle();
    expect(gateway.likes, [('a', DateTime(2026, 9, 22))]);
    expect(find.text('실제 요약 a'), findsOneWidget);
    expect(find.text('총 2개'), findsOneWidget);
  });

  testWidgets('an unlike and its undo change the row in place, without a '
      'reload', (tester) async {
    final gateway = FakeLikes()
      ..rows = [card('a'), card('b'), card('c')]
      ..pageSize = 2;
    await pump(tester, gateway);
    final loads = gateway.requests.length;

    await tester.tap(find.byTooltip('보관 취소').first);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AppLoadingView), findsNothing);
    await tester.pumpAndSettle();
    expect(gateway.requests.length, loads);
    expect(find.text('실제 요약 a'), findsNothing);
    expect(find.text('실제 요약 b'), findsOneWidget);
    expect(find.text('총 2개'), findsOneWidget);

    await tester.tap(find.text('실행 취소'));
    await tester.pumpAndSettle();
    expect(gateway.requests.length, loads);
    expect(find.text('실제 요약 a'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('실제 요약 a')).dy,
      lessThan(tester.getTopLeft(find.text('실제 요약 b')).dy),
    );
    expect(find.text('총 3개'), findsOneWidget);

    // The next page starts after the two rows shown.
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();
    expect(gateway.requests.last.offset, 2);
    expect(find.text('실제 요약 c'), findsOneWidget);
  });

  testWidgets('an undo after leaving and coming back shows the card again', (
    tester,
  ) async {
    final gateway = FakeLikes();
    var revision = 0;
    var shown = true;
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return shown
                  ? SavedCardsScreen(
                      key: ValueKey<int>(revision),
                      gateway: gateway,
                      revision: revision,
                      onChangedAway: () => setState(() => revision++),
                    )
                  : const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('보관 취소').first);
    await tester.pumpAndSettle();
    expect(find.text('실제 요약 a'), findsNothing);

    // Leave while the undo is still offered, then come back to a new screen.
    setOuter(() => shown = false);
    await tester.pumpAndSettle();
    setOuter(() => shown = true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('실행 취소'));
    await tester.pumpAndSettle();
    expect(find.text('실제 요약 a'), findsOneWidget);
  });

  testWidgets('a long name and line fit the card at every width', (
    tester,
  ) async {
    const summary =
        '싱그러운 베리 향과 달콤한 풍미, 톡 쏘는 탄산, 은은하게 맴도는 여운까지 '
        '빈틈없이 마음에 쏙 들었어요. 다음에도 이런 술을 찾아보세요.';
    for (final width in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.3]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(20),
                  child: LikedRecordCard(
                    record: LikedCard(
                      id: 'a',
                      title: '라프로익 10년 캐스크 스트렝스 배치 15 한정판 스페셜 에디션 싱글 몰트',
                      summary: summary,
                      note: '메모',
                      category: 'korean_traditional',
                      recordedAt: DateTime(2026, 11, 6),
                      likedAt: DateTime(2026, 11, 6),
                    ),
                    onUnlike: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$width × $scale');
        final line = tester.renderObject<RenderParagraph>(
          find.textContaining('싱그러운'),
        );
        if (scale == 1) {
          expect(line.didExceedMaxLines, isTrue);
          expect(
            line.size.height,
            line.getMinIntrinsicHeight(line.size.width),
            reason: 'all three lines show at $width',
          );
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('with nothing kept, the list says so in words alone', (
    tester,
  ) async {
    await pump(tester, FakeLikes()..rows = []);
    expect(find.text('보관한 술결 카드가 없어요.'), findsOneWidget);
    expect(find.text('선택한 주종에 보관된 술결 카드가 없어요.'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppEmptyView),
        matching: find.byType(AppIcon),
      ),
      findsNothing,
    );
  });

  testWidgets('load error is not empty and retry restores real list', (
    tester,
  ) async {
    final gateway = FakeLikes()..failLoad = true;
    await pump(tester, gateway);
    expect(find.text('총 —개'), findsOneWidget);
    expect(find.text('선택한 주종에 보관된 술결 카드가 없어요.'), findsNothing);
    gateway.failLoad = false;
    expect(find.text('보관한 술결 카드를 불러오지 못했어요'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('총 2개'), findsOneWidget);
  });

  testWidgets('more loads the next page and a filter resets offset', (
    tester,
  ) async {
    final gateway = FakeLikes()..pageSize = 1;
    await pump(tester, gateway);
    expect(find.text('총 2개'), findsOneWidget);
    expect(find.text('실제 요약 b'), findsNothing);
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();
    expect(gateway.requests.last.offset, 1);
    expect(find.text('실제 요약 b'), findsOneWidget);
    expect(find.text('더 보기'), findsNothing);
    await tester.tap(find.text('와인').first);
    await tester.pumpAndSettle();
    expect(gateway.requests.last.offset, 0);
  });

  group('after a like or a note changed on an opened card', () {
    late FakeLikes gateway;
    late StateSetter setOuter;
    var revision = 0;

    /// Eight cards, three to a page, all shown and scrolled down.
    Future<ScrollPosition> pumpScrolledList(WidgetTester tester) async {
      gateway = FakeLikes()
        ..rows = [for (final id in 'abcdefgh'.split('')) card(id)]
        ..pageSize = 3;
      revision = 0;
      tester.view.physicalSize = const Size(411, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setOuter = setState;
                return SavedCardsScreen(gateway: gateway, revision: revision);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var page = 0; page < 2; page++) {
        await tester.ensureVisible(find.text('더 보기'));
        await tester.tap(find.text('더 보기'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('실제 요약 g'));
      await tester.pumpAndSettle();
      return Scrollable.of(tester.element(find.text('실제 요약 g'))).position;
    }

    testWidgets('the rows shown are read again behind the list, which stays '
        'where it is', (tester) async {
      final position = await pumpScrolledList(tester);
      final scrolledTo = position.pixels;
      expect(scrolledTo, greaterThan(0));
      gateway.requests.clear();

      // On the opened card: one like taken back, one note written.
      gateway
        ..rows = [
          for (final row in gateway.rows)
            if (row.id == 'g')
              card('g', note: '새 메모')
            else if (row.id != 'b')
              row,
        ]
        ..pendingFetch = Completer<void>();
      setOuter(() => revision++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // While the answer is on its way: the same rows, no spinner, no jump.
      expect(find.byType(AppLoadingView), findsNothing);
      expect(find.text('실제 요약 g'), findsOneWidget);
      expect(find.text('총 8개'), findsOneWidget);
      expect(position.pixels, scrolledTo);

      gateway.pendingFetch!.complete();
      await tester.pumpAndSettle();
      // As many rows as were shown, a page at a time from the top.
      expect(
        [for (final request in gateway.requests) request.offset],
        [0, 3, 6],
      );
      expect(find.text('총 7개'), findsOneWidget);
      expect(find.text('실제 요약 g'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('liked-card-note-g')),
        findsOneWidget,
      );
      expect(position.pixels, greaterThan(0));
      expect(find.text('더 보기'), findsNothing);
    });

    testWidgets('rows that cannot be read again stay as they were', (
      tester,
    ) async {
      final position = await pumpScrolledList(tester);
      final scrolledTo = position.pixels;
      gateway.failLoad = true;
      setOuter(() => revision++);
      await tester.pumpAndSettle();
      expect(find.text('실제 요약 g'), findsOneWidget);
      expect(find.text('총 8개'), findsOneWidget);
      expect(position.pixels, scrolledTo);
      expect(find.byType(AppErrorView), findsNothing);
    });
  });

  group('small marks take a tap around them', () {
    testWidgets('the heart, up to a tap target from the photo corner', (
      tester,
    ) async {
      final gateway = FakeLikes();
      await pump(tester, gateway);
      // The heart is 32pt, 4pt in from the photo's corner.
      final heart = tester.getRect(find.byType(AppIconButton).first);
      expect(heart.size, const Size.square(32));
      await tester.tapAt(heart.topLeft + const Offset(-3, -3));
      await tester.pumpAndSettle();
      expect(gateway.removed, ['a']);

      final next = tester.getRect(find.byType(AppIconButton).first);
      await tester.tapAt(next.topLeft + const Offset(39, 39));
      await tester.pumpAndSettle();
      expect(gateway.removed, ['a', 'b']);
    });

    testWidgets('the memo mark, a tap target up and left of it', (
      tester,
    ) async {
      final opened = <String>[];
      final gateway = FakeLikes()..rows = [card('a', note: '다시 마시고 싶어요')];
      await pump(tester, gateway, onOpenCard: opened.add);
      final mark = tester.getRect(
        find.byKey(const ValueKey<String>('liked-card-note-a')),
      );
      expect(mark.height, lessThan(44));

      await tester.tapAt(mark.bottomRight + const Offset(-42, -42));
      await tester.pumpAndSettle();
      expect(find.text('다시 마시고 싶어요'), findsOneWidget);
      expect(opened, isEmpty, reason: 'the card itself is not opened');
    });

    testWidgets('a kind chip, down to a tap target from its top', (
      tester,
    ) async {
      final gateway = FakeLikes();
      await pump(tester, gateway);
      final chip = tester.getRect(find.text('위스키').first);
      final row = tester.getRect(find.byType(AppFilterChip).first);
      expect(row.height, 34);
      await tester.tapAt(Offset(chip.center.dx, row.top + 43));
      await tester.pumpAndSettle();
      expect(gateway.requests.last.category, 'whisky');
    });
  });
}
