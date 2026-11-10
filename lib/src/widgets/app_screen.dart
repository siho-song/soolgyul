import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/app_layout.dart';
import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_debug_layout_guides.dart';
import 'browser_safe_area.dart';

const _hideDebugLayoutGuides = bool.fromEnvironment('SOOL_DESIGN_QA');

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
    this.pageDescription,
    this.pageDescriptionTextAlign = TextAlign.center,
    this.pageDescriptionStyle,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final bool extendBodyIntoTopSafeArea;
  final String? pageDescription;
  final TextAlign pageDescriptionTextAlign;
  final TextStyle? pageDescriptionStyle;

  @override
  Widget build(BuildContext context) {
    final body = pageDescription == null
        ? child
        : NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return <Widget>[
                SliverToBoxAdapter(
                  child: AppPageDescription(
                    pageDescription!,
                    textAlign: pageDescriptionTextAlign,
                    style: pageDescriptionStyle,
                  ),
                ),
              ];
            },
            body: child,
          );
    final scaffold = Scaffold(
      backgroundColor: AppColors.surfaceCanvas,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      body: extendBodyIntoTopSafeArea
          ? body
          : SafeArea(top: appBar == null, child: body),
    );
    final screen = Stack(
      children: <Widget>[
        Positioned.fill(child: scaffold),
        if (kDebugMode && kIsWeb && !_hideDebugLayoutGuides)
          Positioned.fill(
            child: IgnorePointer(
              child: AppDebugLayoutGuides(
                headerHeight: appBar?.preferredSize.height ?? 0,
              ),
            ),
          ),
      ],
    );

    // A desktop browser has no phone insets, so it shows the same iPhone 17
    // screen the design was made for; phone browsers use their real insets.
    if (kIsWeb && (kDebugMode || _isDesktopBrowser)) {
      return ColoredBox(
        color: AppColors.surfaceCanvas,
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

    return ColoredBox(
      color: AppColors.surfaceCanvas,
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

class AppPageDescription extends StatelessWidget {
  const AppPageDescription(
    this.text, {
    super.key,
    this.textAlign = TextAlign.center,
    this.style,
  });

  final String text;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenX,
      AppSpacing.xs,
      AppSpacing.screenX,
      AppSpacing.pageDescriptionToContent,
    ),
    child: Text(text, textAlign: textAlign, style: style ?? AppTextStyles.body),
  );
}
