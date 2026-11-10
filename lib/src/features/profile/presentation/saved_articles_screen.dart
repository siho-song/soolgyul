import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../../editorial/data/editorial_article_gateway.dart';
import '../../editorial/data/editorial_article.dart';
import '../../explore/data/explore_tag.dart';
import '../../explore/presentation/widgets/explore_feed_widgets.dart';
import '../../../widgets/app_state_view.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_snack_bar.dart';

/// The posts the reader bookmarked, newest save first, as covers in the
/// explore feed's two columns. A drink hashtag narrows them; a post is
/// un-bookmarked from its own page.
class SavedArticlesScreen extends StatefulWidget {
  const SavedArticlesScreen({this.gateway, this.onOpenArticle, super.key});

  /// `null` shows an empty list (previews and tests).
  final EditorialArticleGateway? gateway;
  final ValueChanged<EditorialArticle>? onOpenArticle;

  @override
  State<SavedArticlesScreen> createState() => _SavedArticlesScreenState();
}

class _SavedArticlesScreenState extends State<SavedArticlesScreen> {
  ExploreTag? _tag;
  List<EditorialArticle>? _articles;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gateway = widget.gateway;
    if (gateway == null) {
      setState(() => _articles = const <EditorialArticle>[]);
      return;
    }
    setState(() {
      _articles = null;
      _loadError = null;
    });
    try {
      final articles = await gateway.fetchSavedArticles();
      if (!mounted) return;
      setState(() => _articles = articles);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  /// Pulled down: the posts on screen stay until the new ones arrive, and
  /// stay if they do not.
  Future<void> _refresh() async {
    final gateway = widget.gateway;
    if (gateway == null || _articles == null) return _load();
    try {
      final articles = await gateway.fetchSavedArticles();
      if (!mounted) return;
      setState(() => _articles = articles);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '저장한 이야기를 새로 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  List<EditorialArticle> get _visible => <EditorialArticle>[
    for (final article in _articles ?? const <EditorialArticle>[])
      if (_tag?.matches(article) ?? true) article,
  ];

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return MainTabScrollView(
      topPadding: AppSpacing.sm,
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ExploreTagRow(
            selected: _tag,
            onSelected: (tag) =>
                setState(() => _tag = _tag == tag ? null : tag),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loadError != null)
            AppErrorView(title: '저장한 이야기를 불러오지 못했어요', onRetry: _load)
          else if (_articles == null)
            const AppLoadingView()
          else if (visible.isEmpty)
            const AppEmptyView(
              icon: AppIconAsset.search,
              message: '저장한 이야기가 아직 없어요.',
            )
          else
            ExploreArticleGrid(
              articles: visible,
              onOpen: widget.onOpenArticle ?? (_) {},
            ),
        ],
      ),
    );
  }
}
