import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_icon.dart';

enum AppListRowDensity { compact, regular }

enum AppListRowInset { none, standard }

class AppListRow extends StatelessWidget {
  const AppListRow({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.leadingIcon,
    this.trailing,
    this.onPressed,
    this.showChevron = true,
    this.showDivider = true,
    this.density = AppListRowDensity.regular,
    this.inset = AppListRowInset.standard,
    this.chevronIcon = AppIconAsset.next,
  }) : assert(leading == null || leadingIcon == null);

  final String title;
  final String? subtitle;
  final Widget? leading;
  final AppIconAsset? leadingIcon;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final bool showChevron;
  final bool showDivider;
  final AppListRowDensity density;
  final AppListRowInset inset;
  final AppIconAsset chevronIcon;

  @override
  Widget build(BuildContext context) {
    final metrics = _ListRowMetrics.fromDensity(density);
    final row = Container(
      constraints: BoxConstraints(minHeight: metrics.minimumHeight),
      padding: EdgeInsets.symmetric(
        horizontal: inset == AppListRowInset.none
            ? 0
            : metrics.horizontalPadding,
        vertical: metrics.verticalPadding,
      ),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppColors.borderSubtle))
            : null,
      ),
      child: Row(
        children: <Widget>[
          if (leading != null || leadingIcon != null) ...<Widget>[
            leading ??
                AppIcon(
                  leadingIcon!,
                  size: metrics.iconSize,
                  color: AppColors.actionPrimaryStrong,
                ),
            SizedBox(width: metrics.leadingGap),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metrics.titleStyle,
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: metrics.subtitleStyle,
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
          if (trailing == null && showChevron)
            AppIcon(
              chevronIcon,
              size: metrics.chevronSize,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );

    if (onPressed == null) {
      return row;
    }

    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onPressed, child: row),
      ),
    );
  }
}

class _ListRowMetrics {
  const _ListRowMetrics({
    required this.minimumHeight,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.iconSize,
    required this.leadingGap,
    required this.chevronSize,
    required this.titleStyle,
    required this.subtitleStyle,
  });

  final double minimumHeight;
  final double horizontalPadding;
  final double verticalPadding;
  final double iconSize;
  final double leadingGap;
  final double chevronSize;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;

  factory _ListRowMetrics.fromDensity(AppListRowDensity density) {
    return switch (density) {
      AppListRowDensity.compact => const _ListRowMetrics(
        minimumHeight: AppSizes.menuRowHeight,
        horizontalPadding: 14,
        verticalPadding: 8,
        iconSize: 22,
        leadingGap: 18,
        chevronSize: 20,
        titleStyle: AppTextStyles.menuItemTitle,
        subtitleStyle: AppTextStyles.body,
      ),
      AppListRowDensity.regular => const _ListRowMetrics(
        minimumHeight: 58,
        horizontalPadding: 16,
        verticalPadding: 12,
        iconSize: 24,
        leadingGap: 18,
        chevronSize: 22,
        titleStyle: AppTextStyles.cardTitle,
        subtitleStyle: AppTextStyles.body,
      ),
    };
  }
}
