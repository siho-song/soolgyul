import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design/app_layout.dart';
import '../design/app_tokens.dart';

class MainTabScrollView extends StatelessWidget {
  const MainTabScrollView({
    required this.child,
    super.key,
    this.topPadding = 34,
    this.bottomPadding = AppPageScrollView.endGap,
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

class AppPageScrollView extends StatefulWidget {
  const AppPageScrollView({
    required this.child,
    super.key,
    this.topPadding = 0,
    this.bottomPadding = endGap,
    this.onRefresh,
  });

  /// The room under a page's last section: enough to end the page, not a
  /// blank band above the bottom bar, which sits below the page, not on it.
  static const double endGap = AppSpacing.xxxl;

  final Widget child;
  final double topPadding;
  final double bottomPadding;

  /// Pulling the page down runs this and shows the spinner until it ends;
  /// `null` leaves the page without the gesture.
  final Future<void> Function()? onRefresh;

  @override
  State<AppPageScrollView> createState() => _AppPageScrollViewState();
}

class _AppPageScrollViewState extends State<AppPageScrollView> {
  /// The page's content, through which its scroll position is reached; the
  /// scroll view keeps the route's own controller, which a tap on the iOS
  /// status bar scrolls to the top.
  final _content = GlobalKey();

  /// A refresh ends with the page at its top, whatever the reload moved.
  Future<void> _refresh(Future<void> Function() onRefresh) async {
    await onRefresh();
    final content = _content.currentContext;
    if (!mounted || content == null || !content.mounted) return;
    final position = Scrollable.maybeOf(content)?.position;
    if (position != null && position.pixels > 0) {
      await position.animateTo(
        0,
        duration: AppDurations.standard,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!AppLayout.isViewportReady(constraints)) {
        return const SizedBox.shrink();
      }
      final padding = EdgeInsets.only(
        top: widget.topPadding,
        bottom: widget.bottomPadding,
      );
      final onRefresh = widget.onRefresh;
      if (onRefresh == null) {
        return SingleChildScrollView(padding: padding, child: widget.child);
      }
      final content = KeyedSubtree(key: _content, child: widget.child);
      // An iPhone pulls the page itself down and turns its spinner in the
      // room that opens, as the phone's own lists do.
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        return CustomScrollView(
          // A page shorter than the screen can still be pulled.
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: <Widget>[
            CupertinoSliverRefreshControl(onRefresh: () => _refresh(onRefresh)),
            SliverPadding(
              padding: padding,
              sliver: SliverToBoxAdapter(child: content),
            ),
          ],
        );
      }
      return RefreshIndicator(
        onRefresh: () => _refresh(onRefresh),
        // A page shorter than the screen can still be pulled.
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          child: content,
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
