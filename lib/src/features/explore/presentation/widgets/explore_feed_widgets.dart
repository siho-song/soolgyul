import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_filter_chip.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_tap_slop.dart';
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
  Widget build(BuildContext context) => AppTapSlop(
    slop: AppFilterChip.rowTapSlop,
    along: Axis.horizontal,
    child: SizedBox(
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
                child: _GalleryMark(),
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

/// The mark on a cover that has more pictures behind it: white, over its
/// own soft shadow so it reads on a light picture too.
class _GalleryMark extends StatelessWidget {
  const _GalleryMark();

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: const AppIcon(
          AppIconAsset.stack,
          size: AppSizes.iconSm,
          color: AppColors.textPrimary,
        ),
      ),
      const AppIcon(
        AppIconAsset.stack,
        size: AppSizes.iconSm,
        color: AppColors.textOnPrimary,
      ),
    ],
  );
}
