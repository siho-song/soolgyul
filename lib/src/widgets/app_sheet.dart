import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'kept_text.dart';

/// Opens the app's bottom sheet. Every sheet (a short question, a short
/// form, a search, a long list) opens through it, so they all look and move
/// alike. A question that only wants a yes or no opens as a popup instead
/// (`showAppDialog`).
///
/// A short sheet floats a little above the bottom of the screen with all
/// its corners rounded, and has no drag handle. A sheet holding a search or
/// a long list passes [tall]: it sits on the bottom edge, fills most of the
/// screen and keeps its drag handle.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool tall = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: tall ? AppColors.surfaceCanvas : Colors.transparent,
  elevation: tall ? null : 0,
  showDragHandle: tall,
  builder: tall
      ? (context) =>
            FractionallySizedBox(heightFactor: .9, child: builder(context))
      : (context) => _FloatingSheet(child: builder(context)),
);

/// The gap a short sheet keeps from the screen's sides and bottom.
const _floatingGap = AppSpacing.sm;

class _FloatingSheet extends StatelessWidget {
  const _FloatingSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The phone's home bar falls inside the sheet, so only the part of it
    // below the gap is kept clear.
    final bottom = (media.padding.bottom - _floatingGap * 2).clamp(
      0.0,
      double.infinity,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _floatingGap,
        0,
        _floatingGap,
        _floatingGap,
      ),
      child: Material(
        color: AppColors.surfacePrimary,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.sheet)),
        ),
        child: MediaQuery(
          data: media.copyWith(padding: media.padding.copyWith(bottom: bottom)),
          child: child,
        ),
      ),
    );
  }
}

/// Opens a tall sheet holding one long list. The list scrolls inside the
/// sheet; pulled down from its top, it takes the sheet down with it, and let
/// go low or flicked down, the sheet closes, as sheets do in other apps.
Future<T?> showAppScrollingSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController controller)
  builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.surfaceCanvas,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .9,
    maxChildSize: .9,
    // Reaching the bottom closes the sheet; a snap lands at the top or there.
    minChildSize: 0,
    snap: true,
    builder: builder,
  ),
);

/// The space a short sheet's content keeps from the sheet's edges, and
/// above the keyboard when one is open.
EdgeInsets appSheetPadding(BuildContext context) => EdgeInsets.fromLTRB(
  AppSpacing.sheetX,
  AppSpacing.xxxl,
  AppSpacing.sheetX,
  AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
);

/// For a sheet that opens to type in: its field takes [sheetFocus], and the
/// keyboard rises once the sheet has finished sliding up, not while it
/// moves, so the sheet does not jump about on its way in.
mixin FocusWhenSheetOpens<T extends StatefulWidget> on State<T> {
  /// Handed to the sheet's field; the mixin disposes it.
  final sheetFocus = FocusNode();

  Animation<double>? _entrance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final entrance = ModalRoute.of(context)?.animation;
    if (entrance == _entrance) return;
    _entrance?.removeStatusListener(_entranceChanged);
    _entrance = entrance;
    if (entrance == null || entrance.isCompleted) {
      sheetFocus.requestFocus();
    } else {
      entrance.addStatusListener(_entranceChanged);
    }
  }

  void _entranceChanged(AnimationStatus status) {
    if (!status.isCompleted) return;
    _entrance?.removeStatusListener(_entranceChanged);
    if (mounted) sheetFocus.requestFocus();
  }

  @override
  void dispose() {
    _entrance?.removeStatusListener(_entranceChanged);
    sheetFocus.dispose();
    super.dispose();
  }
}

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
      KeptText(title, style: AppTextStyles.sheetTitle),
      if (description case final description?) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        KeptText(description, style: AppTextStyles.sheetBody),
      ],
    ],
  );
}

/// What a sheet shows: a title, a sentence or two, then its buttons: the
/// main one full width (`AppButtonSize.sheet`), and under it a quieter one
/// written only in words (`AppButtonVariant.tertiary`, `AppButtonSize.popup`).
class AppSheetBody extends StatelessWidget {
  const AppSheetBody({
    required this.title,
    required this.body,
    required this.children,
    super.key,
  });

  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: appSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSheetHeading(title: title, description: body),
          const SizedBox(height: AppSpacing.xxxl),
          ...children,
        ],
      ),
    ),
  );
}
