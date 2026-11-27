import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_button.dart';
import 'app_icon.dart';
import '../core/errors/connection_failure.dart';
import 'failure_words.dart';
import 'kept_text.dart';

export 'failure_words.dart';

/// What a screen shows instead of its content: loading, nothing to show, or
/// a failed load. Every screen uses these, so the three states look the same
/// wherever they appear.

/// The spinner while a page or a list loads. [compact] is the same spinner
/// in the short space under rows already shown. [message] is a line under
/// the spinner saying what is loading, where a slow load would otherwise be
/// a blank page.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({
    this.semanticsLabel,
    this.compact = false,
    this.message,
    super.key,
  });

  final String? semanticsLabel;
  final bool compact;
  final String? message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? AppSpacing.md : 48),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          compact
              ? AppSmallSpinner(semanticsLabel: semanticsLabel)
              : CircularProgressIndicator(semanticsLabel: semanticsLabel),
          if (message case final message?) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            KeptText(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
          ],
        ],
      ),
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
/// alone, for a narrow place such as under a search field. [action] is the
/// way out of the empty view, under the line.
class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    required this.message,
    this.icon,
    this.action,
    super.key,
  });

  final String message;
  final AppIconAsset? icon;
  final Widget? action;

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
        if (action case final action?) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          action,
        ],
      ],
    ),
  );
}

/// A page or a list that failed to load: what failed in bold, what to do
/// under it, and the retry. Given the [error] the load failed with, a
/// connection failure is told in the connection's wording instead.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    required this.title,
    required this.onRetry,
    this.description = '잠시 후 다시 시도해 주세요.',
    this.error,
    super.key,
  });

  /// The screen's own words, shown for any failure but the connection's.
  final String title;
  final String description;
  final Object? error;
  final VoidCallback onRetry;

  bool get _offline => isConnectionFailure(error);

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
          _offline ? ConnectionFailureWords.title : title,
          textAlign: TextAlign.center,
          style: AppTextStyles.itemTitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        KeptText(
          _offline ? ConnectionFailureWords.description : description,
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
/// the card, under the card's own title. Given the [error] the load failed
/// with, a connection failure is told in the connection's wording instead.
class AppCardError extends StatelessWidget {
  const AppCardError({
    required this.message,
    required this.onRetry,
    this.error,
    super.key,
  });

  /// The card's own line, shown for any failure but the connection's.
  final String message;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      KeptText(
        failureLine(error, message),
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
