import 'package:flutter/widgets.dart';

import '../design/app_layout.dart';

class MainTabScrollView extends StatelessWidget {
  const MainTabScrollView({
    required this.child,
    super.key,
    this.topPadding = 34,
    this.bottomPadding = 96,
  });

  final Widget child;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => AppPageScrollView(
    topPadding: topPadding,
    bottomPadding: bottomPadding,
    child: AppContentPadding(child: child),
  );
}

class AppPageScrollView extends StatelessWidget {
  const AppPageScrollView({
    required this.child,
    super.key,
    this.topPadding = 0,
    this.bottomPadding = 96,
  });

  final Widget child;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!AppLayout.isViewportReady(constraints)) {
        return const SizedBox.shrink();
      }
      return SingleChildScrollView(
        padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
        child: child,
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
