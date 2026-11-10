import 'package:flutter/material.dart';

import '../design/app_layout.dart';

class MainTabScrollView extends StatelessWidget {
  const MainTabScrollView({
    required this.child,
    super.key,
    this.topPadding = 34,
    this.bottomPadding = 96,
    this.onRefresh,
  });

  final Widget child;
  final double topPadding;
  final double bottomPadding;

  /// See [AppPageScrollView.onRefresh].
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => AppPageScrollView(
    topPadding: topPadding,
    bottomPadding: bottomPadding,
    onRefresh: onRefresh,
    child: AppContentPadding(child: child),
  );
}

class AppPageScrollView extends StatelessWidget {
  const AppPageScrollView({
    required this.child,
    super.key,
    this.topPadding = 0,
    this.bottomPadding = 96,
    this.onRefresh,
  });

  final Widget child;
  final double topPadding;
  final double bottomPadding;

  /// Pulling the page down runs this and shows the spinner until it ends;
  /// `null` leaves the page without the gesture.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!AppLayout.isViewportReady(constraints)) {
        return const SizedBox.shrink();
      }
      final onRefresh = this.onRefresh;
      if (onRefresh == null) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: child,
        );
      }
      return RefreshIndicator(
        onRefresh: onRefresh,
        // A page shorter than the screen can still be pulled.
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: child,
        ),
      );
    },
  );
}

class AppContentPadding extends StatelessWidget {
  const AppContentPadding({
    required this.child,
    super.key,
    this.horizontalPadding,
  });

  final Widget child;
  final double? horizontalPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!AppLayout.isViewportReady(constraints)) {
        return const SizedBox.shrink();
      }
      final layout = AppScreenLayout.fromConstraints(constraints);
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding ?? layout.horizontalPadding,
        ),
        child: child,
      );
    },
  );
}
