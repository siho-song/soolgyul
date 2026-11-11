import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

/// The round check beside a choice: filled when chosen, an empty ring when
/// not.
class AppSelectionMark extends StatelessWidget {
  const AppSelectionMark({required this.selected, super.key});

  static const double size = 20;

  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: AppDurations.fast,
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? AppColors.actionPrimary : Colors.transparent,
      border: Border.all(
        color: selected ? AppColors.actionPrimary : AppColors.borderStrong,
        width: 1.2,
      ),
    ),
    child: selected
        ? const Center(
            child: Icon(
              Icons.check_rounded,
              size: AppSizes.iconXs,
              color: AppColors.textOnPrimary,
            ),
          )
        : null,
  );
}
