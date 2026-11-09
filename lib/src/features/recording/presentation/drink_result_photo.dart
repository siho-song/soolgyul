import 'package:flutter/material.dart';
import '../../../design/app_tokens.dart';
import '../../../widgets/app_icon.dart';

/// Bottle photo for a catalog result; a product without one shows the search
/// icon in the same frame so the names stay aligned.
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
    final placeholder = Center(
      child: AppIcon(
        selected ? AppIconAsset.check : AppIconAsset.search,
        size: size > listSize ? 32 : 20,
        color: selected
            ? AppColors.actionPrimaryStrong
            : AppColors.textTertiary,
        weight: AppIconWeight.strong,
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
