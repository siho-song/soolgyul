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
  const SavedArticlesScreen({
    this.gateway,
    this.onOpenArticle,
    this.revision = 0,
    super.key,
  });

  /// `null` shows an empty list (previews and tests).
  final EditorialArticleGateway? gateway;
  final ValueChanged<EditorialArticle>? onOpenArticle;

  /// Changes when a post opened from here was bookmarked or un-bookmarked
  /// on its own page, so the list loads again.
  final int revision;

  @override
  State<SavedArticlesScreen> createState() => _SavedArticlesScreenState();
}

class _SavedArticlesScreenState extends State<SavedArticlesScreen> {
  ExploreTag? _tag;
  List<EditorialArticle>? _articles;
  Object? _loadError;

  /// Goes up with every read of the list, so a late answer to an older one
  /// is dropped.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SavedArticlesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision) _refresh(pulled: false);
  }

  Future<void> _load() async {
    final gateway = widget.gateway;
    final request = ++_request;
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
      if (!mounted || request != _request) return;
      setState(() => _articles = articles);
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _loadError = error);
    }
  }

  /// Reads the list again with the posts on screen staying until the new
  /// ones arrive. [pulled] down, they stay if those do not, and a notice
  /// says so. Otherwise a bookmark changed on the post's page over this
  /// one: the list would show a post no longer kept, so a failure shows in
  /// its place, with the retry.
  Future<void> _refresh({bool pulled = true}) async {
    final gateway = widget.gateway;
    if (gateway == null || _articles == null) return _load();
    final request = ++_request;
    try {
      final articles = await gateway.fetchSavedArticles();
      if (!mounted || request != _request) return;
      setState(() {
        _articles = articles;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      if (pulled) {
        showAppSnackBar(
          context,
          failureLine(error, '저장한 이야기를 새로 불러오지 못했어요. 잠시 후 다시 시도해 주세요.'),
        );
      } else {
        setState(() => _loadError = error);
      }
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
            AppErrorView(
              title: '저장한 이야기를 불러오지 못했어요',
              error: _loadError,
              onRetry: _load,
            )
          else if (_articles == null)
            const AppLoadingView()
          else if (visible.isEmpty)
            AppEmptyView(
              icon: AppIconAsset.search,
              message: _tag == null
                  ? '저장한 이야기가 아직 없어요.'
                  : '선택한 주종에 저장한 이야기가 없어요.',
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
