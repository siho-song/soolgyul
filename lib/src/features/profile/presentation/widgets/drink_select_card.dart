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
    padding: const EdgeInsets.symmetric(horizontal: 8),
    borderRadius: 12,
    backgroundColor: selected
        ? AppColors.profileInterestSelectedSurface
        : AppColors.surfacePrimary.withValues(alpha: .76),
    borderColor: selected
        ? AppColors.profileInterestSelectedBorder
        : AppColors.profileInterestBorder,
    borderWidth: 1,
    boxShadow: AppShadows.profileInterestCard,
    child: Row(
      children: <Widget>[
        CircleAvatar(
          radius: 17,
          backgroundColor: selected
              ? AppColors.profileInterestSelectedIconSurface
              : AppColors.profileInterestIconSurface,
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
                  size: 26,
                  color: selected
                      ? AppColors.actionPrimaryStrong
                      : AppColors.textWarmTertiary,
                ),
        ),
        const SizedBox(width: 8),
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
        const SizedBox(width: 4),
        _DrinkSelectionIndicator(selected: selected),
      ],
    ),
  );
}

class _DrinkSelectionIndicator extends StatelessWidget {
  const _DrinkSelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? AppColors.actionPrimary : Colors.transparent,
      border: Border.all(
        color: selected
            ? AppColors.actionPrimary
            : AppColors.profileInterestSelectedBorder,
        width: 1.25,
      ),
    ),
    child: selected
        ? const Center(
            child: Icon(
              Icons.check_rounded,
              size: 13,
              color: AppColors.textOnPrimary,
              weight: 450,
            ),
          )
        : null,
  );
}
