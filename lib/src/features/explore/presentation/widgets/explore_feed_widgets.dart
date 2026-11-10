import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_filter_chip.dart';
import '../../../editorial/data/editorial_article.dart';
import '../../../editorial/presentation/widgets/editorial_media_image.dart';
import '../../data/explore_tag.dart';

/// One row of drink hashtags; the selected one, if any, filters the feed.
class ExploreTagRow extends StatelessWidget {
  const ExploreTagRow({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final ExploreTag? selected;
  final ValueChanged<ExploreTag> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppFilterChip.height,
    child: SingleChildScrollView(
      key: const ValueKey<String>('explore-tag-row'),
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: <Widget>[
          for (final tag in ExploreTag.values) ...<Widget>[
            if (tag != ExploreTag.values.first)
              const SizedBox(width: AppSpacing.s6),
            AppFilterChip(
              key: ValueKey<String>('explore-tag-${tag.name}'),
              label: tag.hashtag,
              selected: tag == selected,
              onPressed: () => onSelected(tag),
            ),
          ],
        ],
      ),
    ),
  );
}

class ExploreArticleCard extends StatelessWidget {
  const ExploreArticleCard({
    required this.article,
    required this.onPressed,
    this.semanticsLabel = '이야기 열기',
    this.coverKeyPrefix = 'explore-article',
    super.key,
  });

  final EditorialArticle article;
  final VoidCallback onPressed;
  final String semanticsLabel;

  /// The cover's key is this and the post's id, so a page showing covers
  /// in two places can tell them apart.
  final String coverKeyPrefix;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    child: ClipRRect(
      key: ValueKey<String>('$coverKeyPrefix-${article.id}'),
      borderRadius: BorderRadius.circular(AppRadii.compactCard),
      child: AspectRatio(
        aspectRatio: editorialPhotoAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            EditorialMediaImage(media: article.coverMedia),
            if (article.gallery.length > 1)
              const Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Icon(
                  Icons.filter_none_rounded,
                  size: AppSizes.iconSm,
                  color: AppColors.textOnPrimary,
                  shadows: <Shadow>[Shadow(blurRadius: 4)],
                ),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(onTap: onPressed),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Covers two to a row, in the order given.
class ExploreArticleGrid extends StatelessWidget {
  const ExploreArticleGrid({
    required this.articles,
    required this.onOpen,
    super.key,
  });

  static const _gap = AppSpacing.md;

  final List<EditorialArticle> articles;
  final ValueChanged<EditorialArticle> onOpen;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey<String>('explore-article-grid'),
    children: <Widget>[
      for (var index = 0; index < articles.length; index += 2) ...<Widget>[
        if (index > 0) const SizedBox(height: _gap),
        Row(
          children: <Widget>[
            Expanded(
              child: ExploreArticleCard(
                article: articles[index],
                onPressed: () => onOpen(articles[index]),
              ),
            ),
            const SizedBox(width: _gap),
            Expanded(
              child: index + 1 < articles.length
                  ? ExploreArticleCard(
                      article: articles[index + 1],
                      onPressed: () => onOpen(articles[index + 1]),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    ],
  );
}
