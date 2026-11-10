import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';

enum AppBadgeVariant { soft, outline, solid }

enum AppBadgeSize { tiny, compact, regular, large }

enum AppBadgeTone { brand, preference, neutral }

enum AppBadgeShape { rounded, pill }

class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.label,
    super.key,
    this.variant = AppBadgeVariant.soft,
    this.size = AppBadgeSize.compact,
    this.tone = AppBadgeTone.brand,
    this.shape = AppBadgeShape.pill,
    this.icon,
  });

  final String label;
  final AppBadgeVariant variant;
  final AppBadgeSize size;
  final AppBadgeTone tone;
  final AppBadgeShape shape;
  final AppIconAsset? icon;

  @override
  Widget build(BuildContext context) {
    final metrics = _BadgeMetrics.fromSize(size);
    final colors = _BadgeColors.resolve(variant: variant, tone: tone);
    final borderRadius = shape == AppBadgeShape.pill
        ? AppRadii.chip
        : AppRadii.control;

    return Container(
      constraints: BoxConstraints(minHeight: metrics.minimumHeight),
      padding: EdgeInsets.symmetric(
        horizontal: metrics.horizontalPadding,
        vertical: metrics.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(borderRadius),
        border: colors.border == null
            ? null
            : Border.all(color: colors.border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            AppIcon(icon!, size: metrics.iconSize, color: colors.foreground),
            SizedBox(width: metrics.iconGap),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(
                color: colors.foreground,
                fontSize: metrics.fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeMetrics {
  const _BadgeMetrics({
    required this.minimumHeight,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.fontSize,
    required this.iconSize,
    required this.iconGap,
  });

  factory _BadgeMetrics.fromSize(AppBadgeSize size) {
    return switch (size) {
      AppBadgeSize.tiny => const _BadgeMetrics(
        minimumHeight: 20,
        horizontalPadding: 7,
        verticalPadding: 5,
        fontSize: 9,
        iconSize: 12,
        iconGap: 4,
      ),
      AppBadgeSize.compact => const _BadgeMetrics(
        minimumHeight: 24,
        horizontalPadding: 8,
        verticalPadding: 5,
        fontSize: 10,
        iconSize: 14,
        iconGap: 5,
      ),
      AppBadgeSize.regular => const _BadgeMetrics(
        minimumHeight: 28,
        horizontalPadding: 11,
        verticalPadding: 5,
        fontSize: 12,
        iconSize: 14,
        iconGap: 5,
      ),
      AppBadgeSize.large => const _BadgeMetrics(
        minimumHeight: 34,
        horizontalPadding: 12,
        verticalPadding: 7,
        fontSize: 13,
        iconSize: 16,
        iconGap: 6,
      ),
    };
  }

  final double minimumHeight;
  final double horizontalPadding;
  final double verticalPadding;
  final double fontSize;
  final double iconSize;
  final double iconGap;
}

class _BadgeColors {
  const _BadgeColors({
    required this.background,
    required this.foreground,
    this.border,
  });

  factory _BadgeColors.resolve({
    required AppBadgeVariant variant,
    required AppBadgeTone tone,
  }) {
    final base = switch (tone) {
      AppBadgeTone.brand => AppColors.actionPrimary,
      AppBadgeTone.preference => AppColors.preferencePrimary,
      AppBadgeTone.neutral => AppColors.textSecondary,
    };
    final strong = switch (tone) {
      AppBadgeTone.brand => AppColors.actionPrimaryStrong,
      AppBadgeTone.preference => AppColors.preferencePrimaryStrong,
      AppBadgeTone.neutral => AppColors.textPrimary,
    };

    return switch (variant) {
      AppBadgeVariant.soft => _BadgeColors(
        background: AppColors.surfaceSoft,
        foreground: strong,
      ),
      AppBadgeVariant.outline => _BadgeColors(
        background: Colors.transparent,
        foreground: strong,
        border: AppColors.borderMuted,
      ),
      AppBadgeVariant.solid => _BadgeColors(
        background: base,
        foreground: AppColors.textOnPrimary,
      ),
    };
  }

  final Color background;
  final Color foreground;
  final Color? border;
}
