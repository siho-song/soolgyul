import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import 'app_icon.dart';
import 'kept_text.dart';

/// Shows the app's notice at the bottom of the screen, replacing one still
/// up. Its second sentence starts on its own line. [actionLabel] with
/// [onAction] adds one action at the right, such as 실행 취소. [success]
/// marks a notice that something was done, with a check in place of the ⓘ.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool success = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      appSnackBar(
        message,
        success: success,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
}

SnackBar appSnackBar(
  String message, {
  bool success = false,
  String? actionLabel,
  VoidCallback? onAction,
}) => SnackBar(
  content: Row(
    children: <Widget>[
      AppIcon(
        success ? AppIconAsset.check : AppIconAsset.info,
        size: AppSizes.iconMd,
        color: AppColors.actionPrimary,
      ),
      const SizedBox(width: AppSpacing.s10),
      Expanded(child: KeptText(message, sentencePerLine: true)),
    ],
  ),
  action: actionLabel == null || onAction == null
      ? null
      : SnackBarAction(label: actionLabel, onPressed: onAction),
);
