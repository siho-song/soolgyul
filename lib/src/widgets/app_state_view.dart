import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_button.dart';
import 'app_icon.dart';
import 'kept_text.dart';

/// What a screen shows instead of its content: loading, nothing to show, or
/// a failed load. Every screen uses these, so the three states look the same
/// wherever they appear.

/// The spinner while a page or a list loads. [compact] is the same spinner
/// in the short space under rows already shown.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({this.semanticsLabel, this.compact = false, super.key});

  final String? semanticsLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? AppSpacing.md : 48),
    child: Center(
      child: compact
          ? AppSmallSpinner(semanticsLabel: semanticsLabel)
          : CircularProgressIndicator(semanticsLabel: semanticsLabel),
    ),
  );
}

/// The small spinner inside a field, a row or a control.
class AppSmallSpinner extends StatelessWidget {
  const AppSmallSpinner({this.color, this.semanticsLabel, super.key});

  static const size = 20.0;

  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: color,
      semanticsLabel: semanticsLabel,
    ),
  );
}

/// Nothing to show: an icon and one line. Without [icon] it is the line
/// alone, for a narrow place such as under a search field.
class AppEmptyView extends StatelessWidget {
  const AppEmptyView({required this.message, this.icon, super.key});

  final String message;
  final AppIconAsset? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: icon == null ? AppSpacing.xxl : 48),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon case final icon?) ...<Widget>[
          AppIcon(icon, size: AppSizes.iconXxl, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.md),
        ],
        KeptText(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
        ),
      ],
    ),
  );
}

/// A page or a list that failed to load: what failed in bold, what to do
/// under it, and the retry.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    required this.title,
    required this.onRetry,
    this.description = '잠시 후 다시 시도해 주세요.',
    super.key,
  });

  final String title;
  final String description;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const AppIcon(
          AppIconAsset.wine,
          size: AppSizes.iconXxl,
          color: AppColors.textTertiary,
        ),
        const SizedBox(height: AppSpacing.s14),
        KeptText(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.itemTitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        KeptText(
          description,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppRetryButton(onPressed: onRetry),
      ],
    ),
  );
}

/// One card of a page that failed to load: a line and the retry, inside
/// the card, under the card's own title.
class AppCardError extends StatelessWidget {
  const AppCardError({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      KeptText(
        message,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMuted,
      ),
      const SizedBox(height: AppSpacing.md),
      AppRetryButton(onPressed: onRetry),
    ],
  );
}

class AppRetryButton extends StatelessWidget {
  const AppRetryButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppButton(
    label: '다시 시도',
    onPressed: onPressed,
    variant: AppButtonVariant.secondary,
    size: AppButtonSize.compact,
    widthMode: AppButtonWidthMode.intrinsic,
  );
}
