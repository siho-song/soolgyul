import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';

/// Opens the app's bottom sheet. Every question the app asks before acting
/// (sign out, delete, restore) uses it, so they all look and move alike.
///
/// A sheet that must be answered passes [dismissible] false: it has no drag
/// handle and neither a tap outside nor a swipe closes it.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.surfaceCanvas,
  showDragHandle: dismissible,
  isDismissible: dismissible,
  enableDrag: dismissible,
  builder: builder,
);

/// What a sheet shows: a title, a sentence or two, then its buttons stacked
/// full width, the main one first.
class AppSheetBody extends StatelessWidget {
  const AppSheetBody({
    required this.title,
    required this.body,
    required this.children,
    this.hasHandle = true,
    super.key,
  });

  final String title;
  final String body;
  final List<Widget> children;

  /// False for a sheet opened with `dismissible: false`, which has no drag
  /// handle above the title.
  final bool hasHandle;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sheetX,
        hasHandle ? AppSpacing.sm : AppSpacing.xxl,
        AppSpacing.sheetX,
        AppSpacing.xxxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSpacing.md),
          Text(body, style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.xxl),
          ...children,
        ],
      ),
    ),
  );
}
