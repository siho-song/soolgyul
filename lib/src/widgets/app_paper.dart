import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

/// The 한지 every page lies on. The paper stays where it is while the
/// page's content scrolls over it, and a page that opens over another
/// brings its own sheet, so nothing shows through while it slides in.
///
/// The picture repeats without a seam at the size its grain was made for.
/// Until it is decoded the box shows the paper's own colour.
class AppPaper extends StatelessWidget {
  const AppPaper({required this.child, super.key});

  final Widget child;

  static const asset = 'assets/images/paper/hanji_page.webp';

  /// The picture's 759 px lie across 346 points.
  static const _pixelsPerPoint = 759 / 346;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.surfaceCanvas,
      image: DecorationImage(
        image: AssetImage(asset),
        repeat: ImageRepeat.repeat,
        alignment: Alignment.topLeft,
        scale: _pixelsPerPoint,
      ),
    ),
    child: child,
  );
}

/// A page of its own, outside the app's shared screen (the label reading
/// and its results), on the same paper: a scaffold that lets it show.
class AppPaperScaffold extends StatelessWidget {
  const AppPaperScaffold({required this.body, this.appBar, super.key});

  final PreferredSizeWidget? appBar;
  final Widget body;

  @override
  Widget build(BuildContext context) => AppPaper(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      body: body,
    ),
  );
}
