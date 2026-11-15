import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/app/app_header_policy.dart';
import 'package:soolgyul/src/design/app_theme.dart';
import 'package:soolgyul/src/design/app_tokens.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_gateway.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_save_state.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/widgets/app_top_bar.dart';

final _article = EditorialArticle(
  id: '72000000-0000-4000-8000-000000000001',
  body: '같은 위스키도 잔에 따라 맛이 달라져요',
  publishedAt: DateTime(2026, 8, 18),
  mediaAssets: const <EditorialMediaAsset>[],
  interestKeys: const <String>['whisky'],
);

/// Answers what the reader saved only when the test lets it.
class _SlowEditorial implements EditorialArticleGateway {
  final saved = Completer<List<EditorialArticle>>();

  @override
  Future<List<EditorialArticle>> fetchSavedArticles() => saved.future;

  @override
  Future<List<EditorialArticle>> fetchPublishedArticles() async =>
      <EditorialArticle>[_article];

  @override
  Future<void> saveArticle(String articleId) async {}

  @override
  Future<void> unsaveArticle(String articleId) async {}
}

Future<void> _pumpHeader(WidgetTester tester, PreferredSizeWidget? header) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(appBar: header),
      ),
    );

final _back = find.byTooltip('이전 화면으로 이동');

void main() {
  testWidgets('a new card has no way back while it is made; one that could '
      'not be made leads back', (tester) async {
    var backs = 0;
    PreferredSizeWidget? header({required bool canGoBack}) =>
        AppHeaderPolicy.build(
          route: AppRoute.onboardingResult,
          onBack: () => backs++,
          onEditorialSave: (_) {},
          resultCanGoBack: canGoBack,
        );

    await _pumpHeader(tester, header(canGoBack: false));
    expect(_back, findsNothing);

    await _pumpHeader(tester, header(canGoBack: true));
    await tester.tap(_back);
    expect(backs, 1);
  });

  testWidgets('the bookmark is dimmed and takes no tap until it is known '
      'whether the post is saved', (tester) async {
    final gateway = _SlowEditorial();
    final save = EditorialArticleSaveState(article: _article, gateway: gateway);
    addTearDown(save.dispose);
    final toggled = <EditorialArticleSaveState>[];
    await _pumpHeader(
      tester,
      AppHeaderPolicy.build(
        route: AppRoute.editorialArticle,
        onBack: () {},
        onEditorialSave: toggled.add,
        editorialSave: save,
      ),
    );
    final bookmark = find.byKey(
      const ValueKey<String>('editorial-article-save'),
    );
    AppTopBarMaterialAction action() =>
        tester.widget<AppTopBarMaterialAction>(bookmark);

    expect(action().onPressed, isNull);
    expect(action().color, AppColors.controlInactive);
    await tester.tap(bookmark, warnIfMissed: false);
    expect(toggled, isEmpty);

    gateway.saved.complete(const <EditorialArticle>[]);
    await tester.pumpAndSettle();
    expect(action().color, AppColors.textPrimary);
    await tester.tap(bookmark);
    expect(toggled, <EditorialArticleSaveState>[save]);
  });
}
