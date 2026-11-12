import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'kept_text.dart';

/// Opens a popup in the middle of the screen: a short question answered
/// with a yes or no, or a notice to confirm. Anything longer, or holding a
/// form or a list, opens as a sheet (`showAppSheet`).
///
/// A popup that must be answered passes [dismissible] false: a tap outside
/// does not close it.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) => showDialog<T>(
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
}
