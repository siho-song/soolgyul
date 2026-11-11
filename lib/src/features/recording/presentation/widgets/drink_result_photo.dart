import '../../../../widgets/drink_photo_placeholder.dart';
import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_network_image.dart';

/// Bottle photo for a catalog result; a product without one shows the
/// placeholder drawing in the same frame so the names stay aligned. A photo
/// still on its way shows the same drawing until it fades in.
class DrinkResultPhoto extends StatelessWidget {
  const DrinkResultPhoto({
    required this.url,
    required this.selected,
    this.size = listSize,
    super.key,
  });

  static const double listSize = 56;

  /// The photo at [url] decoded no taller than a frame of [size]: the files
  /// are 512×640, far more than a list row shows. A list warming its first
  /// photos asks for this same image, so the row finds it already loaded.
  static ImageProvider imageFor(
    String url, {
    required double pixelRatio,
    double size = listSize,
  }) => ResizeImage.resizeIfNeeded(
    null,
    (size * pixelRatio).ceil(),
    networkImageProvider(url),
  );

  final String? url;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = selected
        ? Center(
            child: AppIcon(
              AppIconAsset.check,
              size: size > listSize ? AppSizes.iconXxl : AppSizes.iconMd,
              color: AppColors.actionPrimaryStrong,
            ),
          )
        : const DrinkPhotoPlaceholder();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: url == null
          ? placeholder
          : Image(
              image: imageFor(
                url!,
                pixelRatio: MediaQuery.devicePixelRatioOf(context),
                size: size,
              ),
              fit: BoxFit.contain,
              // A photo already in memory shows at once; one that has to
              // load trades places with the placeholder instead of popping
              // into an empty frame.
              frameBuilder: (_, photo, frame, wasSynchronouslyLoaded) =>
                  wasSynchronouslyLoaded
                  ? photo
                  : Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        AnimatedOpacity(
                          opacity: frame == null ? 1 : 0,
                          duration: AppDurations.standard,
                          child: placeholder,
                        ),
                        AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: AppDurations.standard,
                          child: photo,
                        ),
                      ],
                    ),
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
