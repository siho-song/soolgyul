import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';

/// Opens the app's bottom sheet. Every sheet (a question before acting, a
/// short form, a search, a long list) opens through it, so they all look and
/// move alike.
///
/// A sheet that must be answered passes [dismissible] false: it has no drag
/// handle and neither a tap outside nor a swipe closes it. A sheet holding a
/// search or a long list passes [tall] and fills most of the screen.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
  bool tall = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.surfaceCanvas,
  showDragHandle: dismissible,
  isDismissible: dismissible,
  enableDrag: dismissible,
  builder: tall
      ? (context) =>
            FractionallySizedBox(heightFactor: .9, child: builder(context))
      : builder,
);

/// The space a sheet's content keeps from the sheet's edges: close under the
/// drag handle, and above the keyboard when one is open.
EdgeInsets appSheetPadding(BuildContext context, {bool hasHandle = true}) =>
    EdgeInsets.fromLTRB(
      AppSpacing.sheetX,
      hasHandle ? AppSpacing.sm : AppSpacing.xxl,
      AppSpacing.sheetX,
      AppSpacing.xxl + MediaQuery.viewInsetsOf(context).bottom,
    );

/// A sheet's title and the sentence or two under it.
class AppSheetHeading extends StatelessWidget {
  const AppSheetHeading({required this.title, this.description, super.key});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(title, style: AppTextStyles.sectionTitle),
      if (description case final description?) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        Text(description, style: AppTextStyles.modalBody),
      ],
    ],
  );
}

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
      padding: appSheetPadding(context, hasHandle: hasHandle),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSheetHeading(title: title, description: body),
          const SizedBox(height: AppSpacing.xxl),
          ...children,
        ],
      ),
    ),
  );
}
