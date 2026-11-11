import '../widgets/explore_feed_widgets.dart';
import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_article_background.dart';
import '../../../../widgets/app_page_indicator.dart';
import '../../../editorial/data/editorial_article_gateway.dart';
import '../../../editorial/data/editorial_article.dart';
import '../../../editorial/presentation/widgets/editorial_media_image.dart';
import '../../data/explore_tag.dart';

/// A post read like a card-news story: the swipeable photos first, then the
/// plain-text body when the post has one, its hashtags, and the covers of
/// related posts.
class EditorialArticleDetailScreen extends StatefulWidget {
  const EditorialArticleDetailScreen({
    required this.article,
    required this.gateway,
    this.onOpenArticle,
    super.key,
  });

  final EditorialArticle article;
  final EditorialArticleGateway gateway;

  /// Opens a related post; `null` lists none.
  final ValueChanged<EditorialArticle>? onOpenArticle;

  @override
  State<EditorialArticleDetailScreen> createState() =>
      _EditorialArticleDetailScreenState();
}

class _EditorialArticleDetailScreenState
    extends State<EditorialArticleDetailScreen> {
  List<EditorialArticle> _related = const <EditorialArticle>[];

  @override
  void initState() {
    super.initState();
    if (widget.onOpenArticle != null) _loadRelated();
  }

  Future<void> _loadRelated() async {
    try {
      final articles = await widget.gateway.fetchPublishedArticles();
      if (!mounted) return;
      setState(() => _related = relatedArticles(widget.article, articles));
    } catch (_) {
      // The post reads fine without its related row.
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final photos = article.gallery;
    return SingleChildScrollView(
      child: AppArticleBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: AppSpacing.sm),
            // The photos run edge to edge; everything else keeps the gutter.
            if (photos.isNotEmpty) ...<Widget>[
              _CardViewer(photos: photos),
              const SizedBox(height: AppSpacing.lg),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
                child: Divider(height: 1, color: AppColors.borderSubtle),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                0,
                AppSpacing.screenX,
                AppSpacing.massive,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (article.body.trim().isNotEmpty) ...<Widget>[
                    SelectableText(
                      article.body,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        height: 1.75,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Text(
                    hashtagsFor(article).join(' '),
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.actionPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_related.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    const Divider(height: 1, color: AppColors.borderSubtle),
                    const SizedBox(height: AppSpacing.xl),
                    const Text(
                      '함께 읽기 좋은 이야기',
                      style: AppTextStyles.sectionTitle,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _RelatedRow(
                      articles: _related,
                      onOpen: widget.onOpenArticle!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The post's interests as feed hashtags.
List<String> hashtagsFor(EditorialArticle article) => <String>[
  for (final tag in ExploreTag.values)
    if (tag.matches(article)) tag.hashtag,
];

/// Up to six other posts, the ones sharing an interest first, newest first
/// within a rank.
List<EditorialArticle> relatedArticles(
  EditorialArticle article,
  List<EditorialArticle> candidates,
) {
  bool shares(EditorialArticle other) =>
      other.interestKeys.any(article.hasInterest);
  final others = candidates.where((other) => other.id != article.id).toList()
    ..sort((a, b) {
      final byShared = (shares(b) ? 1 : 0).compareTo(shares(a) ? 1 : 0);
      return byShared != 0 ? byShared : b.publishedAt.compareTo(a.publishedAt);
    });
  return others.take(6).toList();
}

/// 3:4 card-news pages swiped horizontally, edge to edge. Like Instagram, a
/// "1/6" counter sits on the photo's top-right and a dot per page below; a
/// single photo shows neither.
class _CardViewer extends StatefulWidget {
  const _CardViewer({required this.photos});

  final List<EditorialMediaAsset> photos;

  @override
  State<_CardViewer> createState() => _CardViewerState();
}

class _CardViewerState extends State<_CardViewer> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;
    return Column(
      children: <Widget>[
        AspectRatio(
          aspectRatio: editorialPhotoAspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PageView.builder(
                key: const ValueKey<String>('editorial-article-gallery'),
                itemCount: count,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) =>
                    EditorialMediaImage(media: widget.photos[index]),
              ),
              if (count > 1)
                Positioned(
                  top: AppSpacing.md,
                  right: AppSpacing.md,
                  child: DecoratedBox(
                    key: const ValueKey<String>('editorial-article-counter'),
                    decoration: BoxDecoration(
                      color: AppColors.scrim.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s10,
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        '${_index + 1}/$count',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textOnPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (count > 1) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          AppPageIndicator(
            count: count,
            activeIndex: _index,
            dotSize: 6,
            dotSpacing: 3,
            activeColor: AppColors.actionPrimary,
            inactiveColor: AppColors.controlInactive,
          ),
        ],
      ],
    );
  }
}

/// Related covers slid sideways: two fit the width with the third peeking
/// in, so readers know there are more.
class _RelatedRow extends StatelessWidget {
  const _RelatedRow({required this.articles, required this.onOpen});

  static const _gap = AppSpacing.md;

  final List<EditorialArticle> articles;
  final ValueChanged<EditorialArticle> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - _gap) / 2.15;
      return SizedBox(
        height: width / editorialPhotoAspectRatio,
        child: ListView.separated(
          key: const ValueKey<String>('editorial-article-related'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          physics: const BouncingScrollPhysics(),
          itemCount: articles.length,
          separatorBuilder: (context, index) => const SizedBox(width: _gap),
          itemBuilder: (context, index) => SizedBox(
            width: width,
            child: ExploreArticleCard(
              article: articles[index],
              onPressed: () => onOpen(articles[index]),
              semanticsLabel: '관련 이야기 열기',
              coverKeyPrefix: 'editorial-related',
            ),
          ),
        ),
      );
    },
  );
}
