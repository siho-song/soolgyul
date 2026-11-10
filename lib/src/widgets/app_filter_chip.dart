import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';

/// One choice in a row of filters above a list (탐색's hashtags, the drink
/// kinds over 보관한 술결 카드): the chosen one is filled wine, the rest are
/// outlined on the page colour.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  static const height = 34.0;

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Material(
      color: selected ? AppColors.actionPrimary : AppColors.surfaceCanvas,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.actionPrimary : AppColors.borderSubtle,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(
                fontSize: 12,
                height: 1,
                color: selected
                    ? AppColors.textOnPrimary
                    : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
