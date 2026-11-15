import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_flow.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary.dart';
import 'package:soolgyul/src/features/profile/data/profile_summary_provider.dart';
import 'package:soolgyul/src/features/profile/presentation/saved_articles_screen.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

import '../support/app_test_harness.dart';

EditorialArticle _post(String id, String body) => EditorialArticle(
  id: '72000000-0000-4000-8000-0000000000$id',
  body: body,
  publishedAt: DateTime(2026, 8, 18),
  mediaAssets: const <EditorialMediaAsset>[],
  interestKeys: const <String>['wine'],
);

final _acidity = _post('01', '산미는 이런 느낌이에요');
final _glass = _post('02', '같은 위스키도 잔에 따라 맛이 달라져요');

Finder _cover(EditorialArticle article) =>
    find.byKey(ValueKey<String>('explore-article-${article.id}'));

/// Keeps the bookmarked posts, newest first, and how often they were read.
class _Bookmarks implements EditorialArticleGateway {
  _Bookmarks(List<EditorialArticle> saved)
    : saved = <EditorialArticle>[...saved];

  final List<EditorialArticle> saved;
  int reads = 0;
  bool failReads = false;

  @override
  Future<List<EditorialArticle>> fetchPublishedArticles() async =>
      <EditorialArticle>[_acidity, _glass];

  @override
  Future<List<EditorialArticle>> fetchSavedArticles() async {
    reads++;
    if (failReads) throw StateError('offline');
    return List<EditorialArticle>.of(saved);
  }

  @override
  Future<void> saveArticle(String articleId) async => saved.insert(
    0,
    <EditorialArticle>[
      _acidity,
      _glass,
    ].firstWhere((article) => article.id == articleId),
  );

  @override
  Future<void> unsaveArticle(String articleId) async =>
      saved.removeWhere((article) => article.id == articleId);
}

void main() {
  testWidgets('a changed bookmark reads the list again, the covers staying '
      'meanwhile', (tester) async {
    final gateway = _Bookmarks(<EditorialArticle>[_acidity, _glass]);
    Widget screen(int revision) =>
        SavedArticlesScreen(gateway: gateway, revision: revision);
    await pumpTestScreen(tester, screen(0));
    await tester.pumpAndSettle();
    expect(_cover(_acidity), findsOneWidget);
    expect(_cover(_glass), findsOneWidget);
    expect(gateway.reads, 1);

    // The same list again asks nothing.
    await pumpTestScreen(tester, screen(0));
    await tester.pumpAndSettle();
    expect(gateway.reads, 1);

    await gateway.unsaveArticle(_acidity.id);
    await pumpTestScreen(tester, screen(1));
    // No spinner takes the list's place while it is read.
    expect(_cover(_glass), findsOneWidget);
    await tester.pumpAndSettle();

    expect(gateway.reads, 2);
    expect(_cover(_acidity), findsNothing);
    expect(_cover(_glass), findsOneWidget);
  });

  testWidgets('a list that cannot be read after a bookmark changed says so '
      'and can be asked for again', (tester) async {
    final gateway = _Bookmarks(<EditorialArticle>[_acidity]);
    Widget screen(int revision) =>
        SavedArticlesScreen(gateway: gateway, revision: revision);
    await pumpTestScreen(tester, screen(0));
    await tester.pumpAndSettle();

    await gateway.unsaveArticle(_acidity.id);
    gateway.failReads = true;
    await pumpTestScreen(tester, screen(1));
    await tester.pumpAndSettle();
    expect(find.text('저장한 이야기를 불러오지 못했어요'), findsOneWidget);
    expect(_cover(_acidity), findsNothing);

    gateway.failReads = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('저장한 이야기가 아직 없어요.'), findsOneWidget);
  });

  testWidgets('a post un-bookmarked on its own page is gone from 저장한 이야기', (
    tester,
  ) async {
    final gateway = _Bookmarks(<EditorialArticle>[_acidity, _glass]);
    final router = AppRouter(
      initialRoute: AppRoute.profile,
      child: AppFlow(
        initialRoute: AppRoute.profile,
        editorialArticleGateway: gateway,
      ),
    );
    addTearDown(router.dispose);
    useTestViewport(tester, const Size(411, 1100));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileSummaryLoaderProvider.overrideWithValue(
            () async => ProfileSummary(
              cardCount: 2,
              savedArticleCount: gateway.saved.length,
              likedCardCount: 0,
            ),
          ),
        ],
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

    await tester.tap(find.text('저장한 이야기'));
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.savedArticles);
    expect(_cover(_acidity), findsOneWidget);
    expect(_cover(_glass), findsOneWidget);

    await tester.tap(_cover(_acidity));
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.editorialArticle);
    await tester.tap(find.byTooltip('게시글 저장 취소'));
    await tester.pumpAndSettle();
    expect(gateway.saved, <EditorialArticle>[_glass]);

    router.pop();
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.savedArticles);
    expect(_cover(_acidity), findsNothing);
    expect(_cover(_glass), findsOneWidget);

    // Bookmarked again from the list's other post's page, it comes back.
    await tester.tap(_cover(_glass));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('게시글 저장 취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('게시글 저장'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(_cover(_glass), findsOneWidget);
  });
}
