import '../../../../widgets/app_selection_mark.dart';
import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_surface.dart';
import '../../data/drink_interest_catalog.dart';

class DrinkSelectCard extends StatelessWidget {
  const DrinkSelectCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final DrinkInterestOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppSurface(
    key: ValueKey<String>('profile-drink-${option.label}'),
    onPressed: onTap,
    semanticLabel: '${option.label} ${selected ? '선택 해제' : '주종 선택'}',
    variant: AppSurfaceVariant.outlined,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    borderRadius: 12,
    backgroundColor: selected
        ? AppColors.profileInterestSelectedSurface
        : AppColors.surfacePrimary.withValues(alpha: .76),
    borderColor: selected
        ? AppColors.profileInterestSelectedBorder
        : AppColors.borderSubtle,
    borderWidth: 1,
    boxShadow: AppShadows.profileInterestCard,
    child: Row(
      children: <Widget>[
        CircleAvatar(
          radius: 17,
          backgroundColor: selected
              ? AppColors.profileInterestSelectedIconSurface
              : AppColors.surfaceSoft,
          child: option.assetPath != null
              ? Image.asset(
                  option.assetPath!,
                  width: 26,
                  height: 26,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                )
              : AppIcon(
                  option.icon,
                  size: AppSizes.iconLg,
                  color: selected
                      ? AppColors.actionPrimaryStrong
                      : AppColors.textWarmTertiary,
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            option.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              fontSize: 12,
              height: 1.2,
              color: selected
                  ? AppColors.actionPrimaryStrong
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        AppSelectionMark(selected: selected),
      ],
    ),
  );
}
