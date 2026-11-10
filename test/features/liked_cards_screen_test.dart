import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('load error is not empty and retry restores real list', (
    tester,
  ) async {
    final gateway = FakeLikes()..failLoad = true;
    await pump(tester, gateway);
    expect(find.text('총 —개'), findsOneWidget);
    expect(find.text('선택한 주종에 보관된 술결 카드가 없어요.'), findsNothing);
    gateway.failLoad = false;
    await tester.tap(find.text('카드를 불러오지 못했어요. 다시 시도'));
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
}
