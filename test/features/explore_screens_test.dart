import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_gateway.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article_save_state.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:soolgyul/src/features/explore/presentation/explore_screens.dart';
import 'package:soolgyul/src/features/profile/presentation/profile_screens.dart';
import 'package:soolgyul/src/widgets/app_page_indicator.dart';

import '../support/app_test_harness.dart';

Finder tag(ExploreTag value) =>
    find.byKey(ValueKey<String>('explore-tag-${value.name}'));

Future<void> tapTag(WidgetTester tester, ExploreTag value) async {
  await tester.ensureVisible(tag(value));
  await tester.tap(tag(value));
  await tester.pumpAndSettle();
}

Finder card(EditorialArticle article) =>
    find.byKey(ValueKey<String>('explore-article-${article.id}'));

Finder related(EditorialArticle article) =>
    find.byKey(ValueKey<String>('editorial-related-${article.id}'));

/// Covers and card pages are portrait 3:4, like Instagram's.
Matcher get isThreeByFour => predicate<Size>(
  (size) => (size.width / size.height - 3 / 4).abs() < 0.01,
  'a 3:4 portrait box',
);

void main() {
  testWidgets('every post of the feed is its cover in the grid', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      ExploreScreen(
        gateway: _FakeEditorialGateway(_posts),
        onOpenArticle: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    for (final value in ExploreTag.values) {
      expect(tag(value), findsOneWidget);
    }
    for (final post in _posts) {
      expect(card(post), findsOneWidget);
      expect(tester.getSize(card(post)), isThreeByFour);
      // The card is the cover alone; none of the text shows.
      expect(find.textContaining(post.body), findsNothing);
    }
    expect(find.byType(AppPageIndicator), findsNothing);
  });

  testWidgets('a hashtag keeps its drink; tapping it again shows all', (
    tester,
  ) async {
    await pumpTestScreen(
      tester,
      ExploreScreen(
        gateway: _FakeEditorialGateway(_posts),
        onOpenArticle: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    await tapTag(tester, ExploreTag.whisky);
    expect(card(_whiskyGlass), findsOneWidget);
    expect(card(_dry), findsOneWidget);
    expect(card(_sakeTemperature), findsNothing);
    expect(card(_naturalWine), findsNothing);

    await tapTag(tester, ExploreTag.whisky);
    expect(card(_sakeTemperature), findsOneWidget);
    expect(card(_naturalWine), findsOneWidget);

    await tapTag(tester, ExploreTag.traditional);
    expect(find.text('아직 등록된 이야기가 없어요.'), findsOneWidget);
  });

  testWidgets('tapping a card opens that post', (tester) async {
    final opened = <String>[];
    await pumpTestScreen(
      tester,
      ExploreScreen(
        gateway: _FakeEditorialGateway(_posts),
        onOpenArticle: (article) => opened.add(article.id),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(card(_whiskyGlass));
    await tester.tap(card(_dry));
    expect(opened, <String>[_whiskyGlass.id, _dry.id]);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    final gateway = _FakeEditorialGateway(_posts, failFirst: true);
    await pumpTestScreen(
      tester,
      ExploreScreen(gateway: gateway, onOpenArticle: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('콘텐츠를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(card(_dry), findsOneWidget);
  });

  testWidgets('editorial detail renders the post and two related posts', (
    tester,
  ) async {
    final opened = <String>[];
    await pumpTestScreen(
      tester,
      EditorialArticleDetailScreen(
        article: _dry,
        gateway: _FakeEditorialGateway(_posts),
        onOpenArticle: (article) => opened.add(article.id),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(_dry.body), findsOneWidget);
    expect(find.text('#위스키'), findsOneWidget);
    expect(find.text('함께 읽기 좋은 이야기'), findsOneWidget);
    // The whisky post ranks first, then the newest of the rest; only their
    // covers show, no text, and the rest slide in from the right.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('editorial-article-related')),
    );
    expect(related(_whiskyGlass), findsOneWidget);
    expect(tester.getSize(related(_whiskyGlass)), isThreeByFour);
    expect(related(_sakeTemperature), findsOneWidget);
    expect(related(_naturalWine), findsNothing);
    expect(find.textContaining(_whiskyGlass.body), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey<String>('editorial-article-related')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(related(_naturalWine), findsOneWidget);

    await tester.ensureVisible(related(_naturalWine));
    await tester.tap(related(_naturalWine));
    expect(opened, <String>[_naturalWine.id]);
  });

  testWidgets('the card viewer counts pages only when there are several', (
    tester,
  ) async {
    final cards = _post(
      '98',
      '카드뉴스 본문',
      interests: const <String>['wine'],
      photos: 3,
    );
    await pumpTestScreen(
      tester,
      EditorialArticleDetailScreen(
        article: cards,
        gateway: _FakeEditorialGateway(<EditorialArticle>[cards]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/3'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('editorial-article-gallery')),
      ),
      isThreeByFour,
    );
    expect(find.byType(AppPageIndicator), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey<String>('editorial-article-gallery')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    await pumpTestScreen(
      tester,
      EditorialArticleDetailScreen(
        article: _dry,
        gateway: _FakeEditorialGateway(<EditorialArticle>[_dry]),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('editorial-article-counter')),
      findsNothing,
    );
    expect(find.byType(AppPageIndicator), findsNothing);
  });

  group('published articles from the gateway', () {
    testWidgets('post detail shows the body and hashtags', (tester) async {
      final gateway = _FakeEditorialGateway(<EditorialArticle>[_article]);

      await pumpTestScreen(
        tester,
        EditorialArticleDetailScreen(article: _article, gateway: gateway),
      );
      await tester.pumpAndSettle();

      expect(find.text('#와인'), findsOneWidget);
      expect(find.textContaining('산미는 이런 느낌이에요'), findsOneWidget);
      expect(find.textContaining('레몬처럼 상큼했어요'), findsOneWidget);
      expect(find.textContaining('읽는 시간'), findsNothing);
    });

    test('the bookmark state persists a save and reports a refusal', () async {
      final gateway = _FakeEditorialGateway(<EditorialArticle>[_article]);
      final state = EditorialArticleSaveState(
        article: _article,
        gateway: gateway,
      );
      addTearDown(state.dispose);

      expect(await state.toggle(), isTrue);
      expect(state.saved, isTrue);
      expect(gateway.savedArticleIds, contains(_article.id));

      gateway.refuseWrites = true;
      expect(await state.toggle(), isFalse);
      expect(state.saved, isTrue);
    });

    testWidgets('saved posts list as covers and a hashtag narrows them', (
      tester,
    ) async {
      final saved = _article.copyWithSavedAt(DateTime(2026, 8, 18));
      final gateway = _FakeEditorialGateway(
        <EditorialArticle>[_article],
        saved: <EditorialArticle>[saved],
      );

      await pumpTestScreen(tester, SavedArticlesScreen(gateway: gateway));
      await tester.pumpAndSettle();

      expect(card(_article), findsOneWidget);
      expect(find.textContaining(_article.body), findsNothing);

      await tapTag(tester, ExploreTag.wine);
      expect(card(_article), findsOneWidget);
      await tapTag(tester, ExploreTag.sake);
      expect(card(_article), findsNothing);
      expect(find.text('저장한 이야기가 아직 없어요.'), findsOneWidget);
    });
  });
}

EditorialArticle _post(
  String id,
  String body, {
  required List<String> interests,
  int photos = 0,
}) => EditorialArticle(
  id: '72000000-0000-4000-8000-0000000000$id',
  body: body,
  publishedAt: DateTime(2026, 8, 18),
  mediaAssets: <EditorialMediaAsset>[
    for (var index = 0; index < photos; index++)
      EditorialMediaAsset(
        id: '73000000-0000-4000-8000-0000000000$id$index',
        storageBucket: 'flutter-assets',
        storageObjectPath:
            'assets/component_assets/explore_feed/beginner_wine_acidity.png',
        sortOrder: index,
      ),
  ],
  interestKeys: interests,
);

final _whiskyGlass = _post(
  '01',
  '같은 위스키도 잔에 따라 맛이 달라져요',
  interests: const <String>['whisky'],
);
final _naturalWineTrend = _post(
  '02',
  '요즘 내추럴 와인이 주목받는 이유',
  interests: const <String>['wine'],
);
final _dry = _post(
  '03',
  '드라이하다는 건 단맛이 적고 깔끔하게 끝나는 느낌이에요',
  interests: const <String>['whisky'],
);
final _sakeTemperature = _post(
  '04',
  '사케는 온도에 따라 맛이 달라져요',
  interests: const <String>['sake'],
);
final _naturalWine = _post(
  '05',
  '집에서 즐기기 좋은 가벼운 한 잔',
  interests: const <String>[],
);
final _posts = <EditorialArticle>[
  _whiskyGlass,
  _naturalWineTrend,
  _dry,
  _sakeTemperature,
  _naturalWine,
];
final _article = _post(
  '06',
  '산미는 이런 느낌이에요\n\n레몬처럼 상큼했어요',
  interests: const <String>['wine'],
  photos: 1,
);

class _FakeEditorialGateway implements EditorialArticleGateway {
  _FakeEditorialGateway(
    this.published, {
    this.saved = const <EditorialArticle>[],
    this.failFirst = false,
  });

  final List<EditorialArticle> published;
  final List<EditorialArticle> saved;
  final List<String> savedArticleIds = <String>[];
  final List<String> unsavedArticleIds = <String>[];
  bool failFirst;
  bool refuseWrites = false;

  @override
  Future<List<EditorialArticle>> fetchPublishedArticles() async {
    if (failFirst) {
      failFirst = false;
      throw const EditorialArticleGatewayException(
        EditorialArticleOperation.fetchPublished,
      );
    }
    return published;
  }

  @override
  Future<List<EditorialArticle>> fetchSavedArticles() async => saved;

  @override
  Future<void> saveArticle(String articleId) async {
    if (refuseWrites) {
      throw const EditorialArticleGatewayException(
        EditorialArticleOperation.save,
      );
    }
    savedArticleIds.add(articleId);
  }

  @override
  Future<void> unsaveArticle(String articleId) async {
    if (refuseWrites) {
      throw const EditorialArticleGatewayException(
        EditorialArticleOperation.unsave,
      );
    }
    unsavedArticleIds.add(articleId);
  }
}
