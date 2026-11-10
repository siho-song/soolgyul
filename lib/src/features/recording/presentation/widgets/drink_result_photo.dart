import '../../../../widgets/drink_photo_placeholder.dart';
import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_network_image.dart';

/// Bottle photo for a catalog result; a product without one shows the
/// placeholder drawing in the same frame so the names stay aligned.
class DrinkResultPhoto extends StatelessWidget {
  const DrinkResultPhoto({
    required this.url,
    required this.selected,
    this.size = listSize,
    super.key,
  });

  static const double listSize = 56;

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
              image: networkImageProvider(url!),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
