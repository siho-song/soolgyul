import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import 'app_icon.dart';

/// How the button sits on what is behind it: `scrim` is a dark circle for
/// use over a photo or the camera, `floating` a light raised circle on a
/// photo's corner.
enum AppIconButtonVariant {
  bare,
  circle,
  outline,
  translucent,
  scrim,
  floating,
}

enum AppIconButtonSize { mini, small, compact, medium, hero }

enum AppIconButtonTone { brand, accent, ink, neutral, inverse }

enum AppIconButtonElevation { flat, raised }

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.onPressed,
    required this.tooltip,
    super.key,
    this.variant = AppIconButtonVariant.bare,
    this.size = AppIconButtonSize.medium,
    this.tone = AppIconButtonTone.brand,
    this.elevation = AppIconButtonElevation.flat,
    this.icon,
    this.child,
  }) : assert(
         (icon == null) != (child == null),
         'give either an icon or a child',
       );

  /// One of the app's icons, drawn at the size's icon size in the tone.
  final AppIconAsset? icon;

  /// A mark the icon set does not have, drawn as given.
  final Widget? child;
  final VoidCallback? onPressed;
  final String tooltip;
  final AppIconButtonVariant variant;
  final AppIconButtonSize size;
  final AppIconButtonTone tone;
  final AppIconButtonElevation elevation;

  @override
  Widget build(BuildContext context) {
    final metrics = _IconButtonMetrics.fromSize(size);
    final colors = _IconButtonColors.resolve(variant: variant, tone: tone);
    final hasCircle = variant != AppIconButtonVariant.bare;

    return Container(
      width: metrics.buttonSize,
      height: metrics.buttonSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: colors.border == null
            ? null
            : Border.all(color: colors.border!),
        boxShadow:
            variant == AppIconButtonVariant.floating ||
                (hasCircle && elevation == AppIconButtonElevation.raised)
            ? AppShadows.floatingControl
            : null,
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          fixedSize: Size.square(metrics.buttonSize),
          minimumSize: Size.square(metrics.buttonSize),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: colors.foreground,
          backgroundColor: colors.background,
          shape: const CircleBorder(),
        ),
        icon:
            child ??
            AppIcon(
              icon!,
              size: metrics.iconSize,
              color: colors.foreground,
              weight: AppIconWeight.strong,
            ),
      ),
    );
  }
}

class _IconButtonMetrics {
  const _IconButtonMetrics({required this.buttonSize, required this.iconSize});

  factory _IconButtonMetrics.fromSize(AppIconButtonSize size) {
    return switch (size) {
      AppIconButtonSize.mini => const _IconButtonMetrics(
        buttonSize: 28,
        iconSize: AppSizes.iconXs,
      ),
      AppIconButtonSize.small => const _IconButtonMetrics(
        buttonSize: 32,
        iconSize: AppSizes.iconSm,
      ),
      AppIconButtonSize.compact => const _IconButtonMetrics(
        buttonSize: AppSizes.minimumTapTarget,
        iconSize: 20,
      ),
      AppIconButtonSize.medium => const _IconButtonMetrics(
        buttonSize: AppSizes.headerButton,
        iconSize: AppSizes.headerIcon,
      ),
      AppIconButtonSize.hero => const _IconButtonMetrics(
        buttonSize: 106,
        iconSize: 44,
      ),
    };
  }

  final double buttonSize;
  final double iconSize;
}

class _IconButtonColors {
  const _IconButtonColors({
    required this.foreground,
    required this.background,
    this.border,
  });

  factory _IconButtonColors.resolve({
    required AppIconButtonVariant variant,
    required AppIconButtonTone tone,
  }) {
    final foreground = switch (tone) {
      AppIconButtonTone.brand => AppColors.actionPrimaryStrong,
      AppIconButtonTone.accent => AppColors.actionPrimary,
      AppIconButtonTone.ink => AppColors.textPrimary,
      AppIconButtonTone.neutral => AppColors.textTertiary,
      AppIconButtonTone.inverse => AppColors.textOnPrimary,
    };

    return switch (variant) {
      AppIconButtonVariant.bare => _IconButtonColors(
        foreground: foreground,
        background: Colors.transparent,
      ),
      AppIconButtonVariant.circle => _IconButtonColors(
        foreground: foreground,
        background: AppColors.surfacePrimary,
      ),
      AppIconButtonVariant.outline => _IconButtonColors(
        foreground: foreground,
        background: Colors.transparent,
        border: AppColors.borderSubtle,
      ),
      AppIconButtonVariant.translucent => _IconButtonColors(
        foreground: foreground,
        background: Colors.white24,
      ),
      AppIconButtonVariant.scrim => _IconButtonColors(
        foreground: foreground,
        background: Colors.black38,
      ),
      AppIconButtonVariant.floating => _IconButtonColors(
        foreground: foreground,
        background: AppColors.surfaceCanvas.withValues(alpha: .92),
        border: AppColors.borderSubtle,
      ),
    };
  }

  final Color foreground;
  final Color background;
  final Color? border;
}
