import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../data/editorial_article.dart';

/// Post photos are portrait 3:4 (1080×1440), the ratio Instagram's feed and
/// grid use, so a photo made for Instagram shows whole here too.
const editorialPhotoAspectRatio = 3 / 4;

class EditorialMediaImage extends StatelessWidget {
  const EditorialMediaImage({
    required this.media,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.high,
    super.key,
  });

  final EditorialMediaAsset? media;
  final BoxFit fit;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final value = media;
    if (value == null) {
      return Container(
        width: width,
        height: height,
        color: AppColors.surfaceSoft,
        alignment: Alignment.center,
        child: const Icon(
          Icons.local_bar_outlined,
          color: AppColors.textTertiary,
        ),
      );
    }
    if (value.isBundledAsset) {
      return Image.asset(
        value.storageObjectPath,
        width: width,
        height: height,
        fit: fit,
        filterQuality: filterQuality,
        errorBuilder: _brokenImage,
      );
    }
    final url = value.publicUrl;
    if (url == null) {
      return const SizedBox.shrink();
    }
    // Decoded no wider than it is shown (a grid cover is half the screen),
    // which keeps the explore grid light on memory and CPU; the frame fades
    // in over the soft surface rather than popping in.
    return LayoutBuilder(
      builder: (context, constraints) {
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final decodeWidth = constraints.hasBoundedWidth
            ? (constraints.maxWidth * pixelRatio).ceil()
            : null;
        return ColoredBox(
          color: AppColors.surfaceSoft,
          child: Image.network(
            url,
            width: width,
            height: height,
            fit: fit,
            filterQuality: filterQuality,
            cacheWidth: decodeWidth,
            frameBuilder: _fadeIn,
            errorBuilder: _brokenImage,
          ),
        );
      },
    );
  }

  static Widget _fadeIn(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: child,
    );
  }

  /// A post whose photo is missing (a bundled path that no longer ships, or
  /// a broken download) keeps its card instead of an error box.
  Widget _brokenImage(BuildContext context, Object error, StackTrace? stack) =>
      Container(
        width: width,
        height: height,
        color: AppColors.surfaceSoft,
        alignment: Alignment.center,
        child: const Icon(
          Icons.broken_image_outlined,
          color: AppColors.textTertiary,
        ),
      );
}
