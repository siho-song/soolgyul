import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_button.dart';
import 'kept_text.dart';

/// Whether popups are drawn as the phone's own alerts: on an iPhone.
bool get _cupertino => defaultTargetPlatform == TargetPlatform.iOS;

/// Opens a popup in the middle of the screen: a short question answered
/// with a yes or no, or a notice to confirm. Anything longer, or holding a
/// form or a list, opens as a sheet (`showAppSheet`).
///
/// On an iPhone it opens the way the phone's own alerts do, and
/// [AppDialogBody] draws one; elsewhere it is the app's own card.
///
/// A popup that must be answered passes [dismissible] false: a tap outside
/// does not close it.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) => _cupertino
    ? showCupertinoDialog<T>(
        context: context,
        barrierDismissible: dismissible,
        builder: builder,
      )
    : showDialog<T>(
        context: context,
        barrierDismissible: dismissible,
        builder: builder,
      );

/// What a popup shows: a title, a sentence or two, then its buttons
/// (`AppButtonSize.popup`). Two buttons sit side by side, the way back
/// (`AppButtonVariant.neutral`) first and the action second; one button
/// fills the width.
///
/// A [centered] popup tells something rather than asks, and centers its
/// words.
///
/// On an iPhone the same title, sentence and buttons are drawn as the
/// phone's own alert, which always centres its words.
class AppDialogBody extends StatelessWidget {
  const AppDialogBody({
    required this.title,
    required this.actions,
    this.body,
    this.centered = false,
    super.key,
  });

  final String title;
  final String? body;
  final List<Widget> actions;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    if (_cupertino) return _buildCupertino();
    final align = centered ? TextAlign.center : TextAlign.start;
    return Dialog(
      backgroundColor: AppColors.surfacePrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.compactCard)),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.xxl,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xxl + AppSpacing.xs,
          AppSpacing.xxl,
          AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            KeptText(title, style: AppTextStyles.popupTitle, textAlign: align),
            if (body case final body?) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              KeptText(body, style: AppTextStyles.sheetBody, textAlign: align),
            ],
            const SizedBox(height: AppSpacing.xxl + AppSpacing.xs),
            Row(
              children: <Widget>[
                for (final (index, action) in actions.indexed) ...<Widget>[
                  if (index > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: action),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The phone's own alert, in the app's typeface: the words centred, the
  /// buttons side by side under a hairline.
  Widget _buildCupertino() => CupertinoAlertDialog(
    title: KeptText(title, style: _appFont),
    content: switch (body) {
      final body? => KeptText(body, style: _appFont),
      null => null,
    },
    actions: <Widget>[
      for (final action in actions)
        action is AppButton ? _cupertinoAction(action) : action,
    ],
  );

  static const _appFont = TextStyle(
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.fallback,
  );

  /// The same button as a row of the alert, under the same key. The way
  /// back is written in ink and the action in the app's colour; a button
  /// that is busy turns, and one that cannot be pressed is dimmed.
  static Widget _cupertinoAction(AppButton button) {
    final wayBack = button.variant == AppButtonVariant.neutral;
    final enabled = !button.isDisabled && !button.isLoading;
    return CupertinoDialogAction(
      key: button.key,
      isDefaultAction: wayBack,
      onPressed: enabled ? button.onPressed : null,
      textStyle: _appFont.copyWith(
        color: wayBack ? AppColors.textPrimary : AppColors.actionPrimary,
      ),
      child: button.isLoading
          ? const CupertinoActivityIndicator()
          : Text(button.label),
    );
  }
}
