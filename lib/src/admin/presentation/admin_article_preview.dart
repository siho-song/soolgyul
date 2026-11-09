import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_header_policy.dart';
import '../../design/app_layout.dart';
import '../../design/app_tokens.dart';
import '../../features/editorial/data/editorial_article_gateway.dart';
import '../../features/editorial/editorial_article.dart';
import '../../features/explore/presentation/screens/editorial_article_detail_screen.dart';
import '../../features/explore/presentation/screens/explore_screen.dart';
import '../../navigation/app_route.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/app_screen.dart';

/// What readers will see, drawn from the editor's current values. The pages
/// are the app's own screens inside a phone viewport, so the preview is the
/// post and the explore list exactly as the app renders them.
class AdminArticlePreview extends StatefulWidget {
  const AdminArticlePreview({
    required this.body,
    required this.interestKeys,
    required this.gallery,
    this.instagramUrl,
    super.key,
  });

  final String body;
  final Set<String> interestKeys;
  final List<EditorialMediaAsset> gallery;
  final String? instagramUrl;

  @override
  State<AdminArticlePreview> createState() => _AdminArticlePreviewState();
}

enum _Mode { article, feed }

class _AdminArticlePreviewState extends State<AdminArticlePreview> {
  _Mode _mode = _Mode.article;

  EditorialArticle get _article => EditorialArticle(
    id: 'admin-preview',
    body: widget.body,
    instagramUrl: widget.instagramUrl,
    publishedAt: DateTime.now(),
    mediaAssets: widget.gallery,
    interestKeys: widget.interestKeys.toList(growable: false),
  );

  /// The explore feed loads its posts once, so it is remounted whenever a
  /// value that changes the feed is edited.
  Object get _contentKey => Object.hash(
    widget.body,
    Object.hashAll(widget.interestKeys),
    Object.hashAll(widget.gallery.map((media) => media.id)),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      SegmentedButton<_Mode>(
        key: const ValueKey<String>('admin-preview-mode'),
        showSelectedIcon: false,
        segments: const <ButtonSegment<_Mode>>[
          ButtonSegment<_Mode>(value: _Mode.article, label: Text('게시글')),
          ButtonSegment<_Mode>(value: _Mode.feed, label: Text('탐색 탭')),
        ],
        selected: <_Mode>{_mode},
        onSelectionChanged: (value) => setState(() => _mode = value.first),
      ),
      const SizedBox(height: AppSpacing.lg),
      _PhoneViewport(
        child: switch (_mode) {
          _Mode.article => _ArticleScreen(article: _article),
          _Mode.feed => _ExploreFeedScreen(
            key: ValueKey<Object>(_contentKey),
            article: _article,
          ),
        },
      ),
    ],
  );
}

/// The app's phone viewport, scaled down to the width available.
class _PhoneViewport extends StatelessWidget {
  const _PhoneViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 380,
    decoration: BoxDecoration(
      color: AppColors.textPrimary,
      borderRadius: BorderRadius.circular(44),
    ),
    padding: const EdgeInsets.all(10),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(36),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox.fromSize(
          size: AppLayout.iPhone17Viewport,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: AppLayout.iPhone17Viewport,
              padding: AppLayout.iPhone17SafeArea,
              viewPadding: AppLayout.iPhone17SafeArea,
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// The post's own page, with the header the app gives it.
class _ArticleScreen extends StatelessWidget {
  const _ArticleScreen({required this.article});

  final EditorialArticle article;

  @override
  Widget build(BuildContext context) => AppScreen(
    appBar: _header(
      AppRoute.editorialArticle,
      onEditorialInstagram: switch (article.instagramUrl) {
        final url? => () => unawaited(
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        ),
        null => null,
      },
    ),
    child: EditorialArticleDetailScreen(
      article: article,
      gateway: _PreviewArticleGateway(article),
    ),
  );
}

/// The explore feed with the post on it, with its header and the bottom
/// navigation.
class _ExploreFeedScreen extends StatelessWidget {
  const _ExploreFeedScreen({required this.article, super.key});

  final EditorialArticle article;

  @override
  Widget build(BuildContext context) => AppScreen(
    appBar: _header(AppRoute.explore),
    bottomNavigationBar: AppBottomNav(
      activeTab: AppTab.explore,
      onTab: (_) {},
      onRecord: (_) {},
      recordIntent: AppRecordIntent.startFlow,
    ),
    child: ExploreScreen(
      onOpenArticle: (_) {},
      gateway: _PreviewArticleGateway(article),
    ),
  );
}

PreferredSizeWidget? _header(
  AppRoute route, {
  VoidCallback? onEditorialInstagram,
}) => AppHeaderPolicy.build(
  route: route,
  onBack: () {},
  onEditorialInstagram: onEditorialInstagram,
  onEditorialShare: () {},
  onEditorialSave: (_) {},
);

/// Serves the previewed post as the only published one; saving is a no-op.
class _PreviewArticleGateway implements EditorialArticleGateway {
  const _PreviewArticleGateway(this.article);

  final EditorialArticle article;

  @override
  Future<List<EditorialArticle>> fetchPublishedArticles() async =>
      <EditorialArticle>[article];

  @override
  Future<List<EditorialArticle>> fetchSavedArticles() async =>
      const <EditorialArticle>[];

  @override
  Future<void> saveArticle(String articleId) async {}

  @override
  Future<void> unsaveArticle(String articleId) async {}
}
