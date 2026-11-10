import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_filter_chip.dart';
import '../../../../widgets/app_icon.dart';
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
            if (tag != ExploreTag.values.first) const SizedBox(width: 6),
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
    super.key,
  });

  final EditorialArticle article;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '이야기 열기',
    child: ClipRRect(
      key: ValueKey<String>('explore-article-${article.id}'),
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
                  size: 16,
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

/// The feed's one-line states: loading failed, or nothing matches.
class ExploreFeedNotice extends StatelessWidget {
  const ExploreFeedNotice.loadFailed({
    required VoidCallback this.onRetry,
    super.key,
  }) : message = '콘텐츠를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
       icon = null;

  const ExploreFeedNotice.empty({this.message = '아직 등록된 이야기가 없어요.', super.key})
    : icon = AppIconAsset.search,
      onRetry = null;

  final String message;
  final AppIconAsset? icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: <Widget>[
        if (icon case final icon?) ...<Widget>[
          AppIcon(icon, size: 30, color: AppColors.textTertiary),
          const SizedBox(height: 12),
        ],
        Text(
          message,
          style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
        ),
        if (onRetry case final retry?) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: retry, child: const Text('다시 시도')),
        ],
      ],
    ),
  );
}
