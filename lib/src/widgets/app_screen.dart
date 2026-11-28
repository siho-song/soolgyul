import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/app_layout.dart';
import 'app_input_popup.dart';
import 'app_paper.dart';
import 'browser_safe_area.dart';

bool get _isDesktopBrowser =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

class AppScreen extends StatelessWidget {
  const AppScreen({
    required this.child,
    super.key,
    this.appBar,
    this.bottomNavigationBar,
    this.extendBodyIntoTopSafeArea = false,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;

  /// For a page whose picture at the top reaches under the status bar.
  final bool extendBodyIntoTopSafeArea;

  @override
  Widget build(BuildContext context) {
    final Widget screen = _PageScaffold(
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      extendBodyIntoTopSafeArea: extendBodyIntoTopSafeArea,
      child: child,
    );

    // A desktop browser has no phone insets, so it shows the same iPhone 17
    // screen the design was made for; phone browsers use their real insets.
    if (kIsWeb && (kDebugMode || _isDesktopBrowser)) {
      return AppPaper(
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ClipRect(
              child: SizedBox.fromSize(
                size: AppLayout.iPhone17Viewport,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: AppLayout.iPhone17Viewport,
                    padding: AppLayout.iPhone17SafeArea,
                    viewPadding: AppLayout.iPhone17SafeArea,
                  ),
                  child: screen,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AppPaper(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.regularPhoneWidth,
          ),
          child: kIsWeb ? _withBrowserSafeArea(context, screen) : screen,
        ),
      ),
    );
  }

  // Flutter web reports no notch or home indicator, so the browser's own
  // insets are merged into the padding SafeArea reads.
  Widget _withBrowserSafeArea(BuildContext context, Widget screen) {
    // Rotating the phone changes the insets, so rebuild on every resize.
    MediaQuery.sizeOf(context);
    final mediaQuery = MediaQuery.of(context);
    final browserSafeArea = readBrowserSafeArea();
    EdgeInsets merge(EdgeInsets reported) => EdgeInsets.fromLTRB(
      math.max(reported.left, browserSafeArea.left),
      math.max(reported.top, browserSafeArea.top),
      math.max(reported.right, browserSafeArea.right),
      math.max(reported.bottom, browserSafeArea.bottom),
    );
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: merge(mediaQuery.padding),
        viewPadding: merge(mediaQuery.viewPadding),
      ),
      child: screen,
    );
  }
}

/// The page itself. It makes room for the keyboard only while one of its
/// own fields is typed in: a keyboard that came up for a popup or a sheet
/// over the page leaves the page, and its bottom menu, where they were.
class _PageScaffold extends StatefulWidget {
  const _PageScaffold({
    required this.child,
    required this.appBar,
    required this.bottomNavigationBar,
    required this.extendBodyIntoTopSafeArea,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final bool extendBodyIntoTopSafeArea;

  @override
  State<_PageScaffold> createState() => _PageScaffoldState();
}

class _PageScaffoldState extends State<_PageScaffold> {
  bool _typing = false;

  @override
  Widget build(BuildContext context) {
    noteKeyboardHeight(MediaQuery.viewInsetsOf(context).bottom);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (typing) => setState(() => _typing = typing),
      child: Scaffold(
        // The paper under the page shows through.
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: _typing,
        appBar: widget.appBar,
        bottomNavigationBar: widget.bottomNavigationBar,
        body: SafeArea(
          top: widget.appBar == null && !widget.extendBodyIntoTopSafeArea,
          child: widget.child,
        ),
      ),
    );
  }
}
