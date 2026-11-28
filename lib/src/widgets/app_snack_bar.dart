import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import 'app_icon.dart';
import 'kept_text.dart';

// A failure's notice is worded by failureLine, which a screen showing one
// needs with the notice.
export 'failure_words.dart';

/// Shows the app's notice at the bottom of the screen, replacing one still
/// up. Its second sentence starts on its own line. [actionLabel] with
/// [onAction] adds one action at the right, such as 실행 취소. [success]
/// marks a notice that something was done, with a check in place of the ⓘ.
/// [liftBy] raises it over a button the page keeps at its bottom.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool success = false,
  String? actionLabel,
  VoidCallback? onAction,
  double liftBy = 0,
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
        liftBy: liftBy,
      ),
    );
}

/// Takes down the notice on screen, when what it says stopped being true.
void hideAppSnackBar(BuildContext context) =>
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();

SnackBar appSnackBar(
  String message, {
  bool success = false,
  String? actionLabel,
  VoidCallback? onAction,
  double liftBy = 0,
}) => SnackBar(
  margin: liftBy == 0
      ? null
      : EdgeInsets.fromLTRB(
          _floatingMargin.left,
          _floatingMargin.top,
          _floatingMargin.right,
          _floatingMargin.bottom + liftBy,
        ),
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

/// Where a floating notice rests when it is given no margin of its own.
const _floatingMargin = EdgeInsets.fromLTRB(15, 5, 15, 10);
