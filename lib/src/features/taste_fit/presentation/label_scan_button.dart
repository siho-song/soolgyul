import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../widgets/app_icon.dart';

/// The small camera pill at the end of a search box: photograph the label
/// instead of typing the name. The home entry and the taste-fit search use
/// the same one.
class LabelScanButton extends StatelessWidget {
  const LabelScanButton({
    required this.onPressed,
    this.label = '사진으로 찾기',
    super.key,
  });

  /// `null` disables the button (a scan is already running).
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: label,
    child: Material(
      color: AppColors.surfaceMuted,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: const SizedBox(
          width: 44,
          height: 36,
          child: Center(
            child: AppIcon(
              AppIconAsset.camera,
              size: 20,
              color: AppColors.actionPrimary,
            ),
          ),
        ),
      ),
    ),
  );
}
