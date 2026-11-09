import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';

class OnboardingDrinkTile extends StatelessWidget {
  const OnboardingDrinkTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.horizontal = false,
    this.emoji,
    super.key,
  });

  final AppIconAsset icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  /// Icon beside the label in a shorter tile, for compact grids.
  final bool horizontal;

  /// Shown instead of [icon] when given.
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
      side: BorderSide(
        color: selected ? AppColors.actionPrimary : const Color(0xFFD9D9D9),
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
                  if (emoji != null)
                    Text(emoji!, style: const TextStyle(fontSize: 18))
                  else
                    AppIcon(
                      icon,
                      color: selected
                          ? AppColors.actionPrimary
                          : AppColors.textSecondary,
                      size: 20,
                    ),
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
                        color: selected
                            ? AppColors.actionPrimary
                            : AppColors.textSecondary,
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
