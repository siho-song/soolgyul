import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';

class OnboardingDrinkTile extends StatelessWidget {
  const OnboardingDrinkTile({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.horizontal = false,
    super.key,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  /// Emoji beside the label in a shorter tile, for compact grids.
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
      side: BorderSide(
        color: selected ? AppColors.actionPrimary : AppColors.controlInactive,
        width: selected ? 1.5 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        height: horizontal ? 48 : 52,
        child: Material(
          color: selected
              ? (horizontal
                    ? AppColors.actionPrimary.withValues(alpha: 0.07)
                    : const Color(0xFFFFF8F7))
              : Colors.white,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontal ? 14 : 6),
              child: Flex(
                direction: horizontal ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  SizedBox(
                    width: horizontal ? AppSpacing.sm : 0,
                    height: horizontal ? 0 : AppSpacing.xs,
                  ),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle(
                        fontSize: horizontal ? 14 : 12,
                        // The text's own dark, picked or not: the edge and
                        // the fill say it is picked.
                        color: AppColors.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
