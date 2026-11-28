import 'package:flutter/material.dart';

import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'app_press_scale.dart';

/// One choice in a row of filters above a list (피드's hashtags, the kinds
/// over 나의 용어 사전): the chosen one is filled wine, the rest are outlined
/// on the page.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  static const height = 34.0;

  /// For an `AppTapSlop` along a row of these: what the chips lack of a tap
  /// target, taken from the gap under the row. A row is often the first
  /// thing on its page, with nothing of the page above it to take.
  static const rowTapSlop = EdgeInsets.only(
    bottom: AppSizes.minimumTapTarget - height,
  );

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: AppPressScale(
      builder: (context, onPressedChanged) => Material(
        // Not chosen, it is an outline on the page's paper.
        color: selected ? AppColors.actionPrimary : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppColors.actionPrimary : AppColors.borderSubtle,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          onHighlightChanged: onPressedChanged,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  fontSize: 13,
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
    ),
  );
}
