import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_page_scroll_view.dart';
import '../../../editorial/data/editorial_article_gateway.dart';
import '../../../editorial/data/editorial_article.dart';
import '../../data/explore_tag.dart';
import '../widgets/explore_feed_widgets.dart';
import '../../../../widgets/app_state_view.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_snack_bar.dart';
import '../../../../core/kept_first.dart';

/// The explore tab: a row of drink hashtags, then every post (or the posts
/// of the chosen tag) as their covers in two columns, newest first.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({required this.onOpenArticle, this.gateway, super.key});

  final ValueChanged<EditorialArticle> onOpenArticle;

  /// `null` shows an empty feed (previews and tests).
  final EditorialArticleGateway? gateway;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
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
    // What the phone kept from last time shows until the server answers.
    if (gateway case final KeepsLast<List<EditorialArticle>> keeper) {
      unawaited(
        keeper.kept().then((kept) {
          if (mounted && kept != null && _articles == null) {
            setState(() => _articles = kept);
          }
        }, onError: (Object _) {}),
      );
    }
    try {
      final articles = await gateway.fetchPublishedArticles();
      if (!mounted) return;
      setState(() => _articles = articles);
    } catch (error) {
      if (!mounted) return;
      // The kept posts stay readable when the server cannot be reached.
      if (_articles == null) setState(() => _loadError = error);
    }
  }

  /// Pulled down: the posts on screen stay until the new ones arrive, and
  /// stay if they do not.
  Future<void> _refresh() async {
    final gateway = widget.gateway;
    if (gateway == null || _articles == null) return _load();
    try {
      final articles = await gateway.fetchPublishedArticles();
      if (!mounted) return;
      setState(() => _articles = articles);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '이야기를 새로 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  /// Tapping the chosen tag again clears it.
  void _selectTag(ExploreTag tag) =>
      setState(() => _tag = _tag == tag ? null : tag);

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
          ExploreTagRow(selected: _tag, onSelected: _selectTag),
          const SizedBox(height: AppSpacing.lg),
          if (_loadError != null)
            AppErrorView(title: '이야기를 불러오지 못했어요', onRetry: _load)
          else if (_articles == null)
            const AppLoadingView()
          else if (visible.isEmpty)
            const AppEmptyView(
              icon: AppIconAsset.search,
              message: '아직 등록된 이야기가 없어요.',
            )
          else
            ExploreArticleGrid(articles: visible, onOpen: widget.onOpenArticle),
        ],
      ),
    );
  }
}
