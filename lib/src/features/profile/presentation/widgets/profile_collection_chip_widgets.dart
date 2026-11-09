import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_surface.dart';
import '../../../editorial/data/editorial_article.dart';
import '../../../editorial/presentation/widgets/editorial_media_image.dart';

/// 좋아요한 술결 카드와 저장한 정보 글 카드가 공유하는 레이아웃 규격입니다.
abstract final class _ProfileCollectionCardMetrics {
  static const padding = EdgeInsets.all(6);
  static const contentPadding = EdgeInsets.fromLTRB(0, 5, 5, 5);
  static const compactHeight = 150.0;
  static const regularHeight = 142.0;
  static const imageWidthFactor = .28;
  static const imageMinWidth = 88.0;
  static const imageMaxWidth = 104.0;
  static const imageRadius = 13.0;
  static const actionSize = 28.0;
  static const actionIconSize = 20.0;
  static const titleFontSize = 12.0;
  static const descriptionCompactFontSize = 10.0;
  static const descriptionFontSize = 11.0;
  static const descriptionHeight = 1.7;
}

/// 저장 컬렉션에서 이미지, 제목, 설명, 우측 액션을 공통으로 배치하는 카드입니다.
///
/// 좋아요한 술결 카드와 저장한 정보 글의 하단 정보만 [footerBuilder]로 교체합니다.
class ProfileCollectionCard extends StatelessWidget {
  const ProfileCollectionCard({
    super.key,
    required this.asset,
    required this.title,
    required this.description,
    required this.actionIcon,
    required this.actionTooltip,
    required this.onAction,
    required this.footerBuilder,
    this.media,
    this.onPressed,
    this.image,
  });

  final String asset;
  final String title;
  final String description;
  final IconData actionIcon;
  final String actionTooltip;
  final VoidCallback? onAction;
  final Widget? image;
  final Widget Function(bool compact) footerBuilder;
  final EditorialMediaAsset? media;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 330;
      final imageWidth =
          (constraints.maxWidth *
                  _ProfileCollectionCardMetrics.imageWidthFactor)
              .clamp(
                _ProfileCollectionCardMetrics.imageMinWidth,
                _ProfileCollectionCardMetrics.imageMaxWidth,
              );

      return AppPanel(
        padding: _ProfileCollectionCardMetrics.padding,
        onPressed: onPressed,
        semanticLabel: onPressed == null ? null : '$title 게시글 열기',
        child: SizedBox(
          height: compact
              ? _ProfileCollectionCardMetrics.compactHeight
              : _ProfileCollectionCardMetrics.regularHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  _ProfileCollectionCardMetrics.imageRadius,
                ),
                child: image != null
                    ? SizedBox(width: imageWidth, child: image)
                    : media == null
                    ? Image.asset(asset, width: imageWidth, fit: BoxFit.cover)
                    : EditorialMediaImage(
                        media: media,
                        width: imageWidth,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
              ),
              SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: _ProfileCollectionCardMetrics.contentPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.cardTitle.copyWith(
                                fontSize:
                                    _ProfileCollectionCardMetrics.titleFontSize,
                                height: 1.25,
                                color: AppColors.textSupporting,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          IconButton(
                            onPressed: onAction,
                            tooltip: actionTooltip,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: _ProfileCollectionCardMetrics.actionSize,
                              height: _ProfileCollectionCardMetrics.actionSize,
                            ),
                            icon: Icon(
                              actionIcon,
                              size:
                                  _ProfileCollectionCardMetrics.actionIconSize,
                              color: AppColors.actionPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: compact
                                ? _ProfileCollectionCardMetrics
                                      .descriptionCompactFontSize
                                : _ProfileCollectionCardMetrics
                                      .descriptionFontSize,
                            height:
                                _ProfileCollectionCardMetrics.descriptionHeight,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      footerBuilder(compact),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 저장 콘텐츠 화면에서 공통으로 사용하는 주종 필터 칩입니다.
class ProfileCollectionFilterChip extends StatelessWidget {
  const ProfileCollectionFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.actionPrimary : AppColors.collectionChipSurface,
    shape: StadiumBorder(
      side: BorderSide(
        color: selected
            ? AppColors.actionPrimary
            : AppColors.collectionChipBorder,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 10,
            color: selected
                ? AppColors.textOnPrimary
                : AppColors.collectionChipText,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

/// Empty result of a saved collection under the selected filter.
class ProfileCollectionEmptyState extends StatelessWidget {
  const ProfileCollectionEmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
    child: Column(
      children: <Widget>[
        Icon(icon, size: 34, color: AppColors.textTertiary),
        const SizedBox(height: AppSpacing.md),
        Text(message, style: AppTextStyles.bodySmall),
      ],
    ),
  );
}
