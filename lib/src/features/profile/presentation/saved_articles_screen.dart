import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../widgets/app_page_scroll_view.dart';
import '../../editorial/data/editorial_article_gateway.dart';
import '../../editorial/editorial_article.dart';
import '../../explore/data/explore_tag.dart';
import '../../explore/presentation/widgets/explore_feed_widgets.dart';

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

  List<EditorialArticle> get _visible => <EditorialArticle>[
    for (final article in _articles ?? const <EditorialArticle>[])
      if (_tag?.matches(article) ?? true) article,
  ];

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return MainTabScrollView(
      topPadding: AppSpacing.sm,
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
            ExploreFeedNotice.loadFailed(onRetry: _load)
          else if (_articles == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visible.isEmpty)
            const ExploreFeedNotice.empty(message: '저장한 글이 아직 없어요.')
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
