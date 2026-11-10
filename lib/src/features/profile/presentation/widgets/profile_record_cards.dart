import 'package:flutter/material.dart';
import '../../../../design/app_feature_layouts.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_section_action.dart';
import '../../data/drink_interest_catalog.dart';
import '../../data/profile_setup_draft.dart';

class ProfileInterestsCard extends StatelessWidget {
  const ProfileInterestsCard({
    super.key,
    required this.labels,
    required this.onPressed,
  });

  final Set<DrinkInterest> labels;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final selectedOptions = drinkInterestOptions
        .where((option) => labels.contains(option.value))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text('관심 주종', style: AppTextStyles.sectionTitle),
            ),
            AppSectionAction(
              key: const ValueKey<String>('profile-interest-settings'),
              label: '설정',
              semanticLabel: '관심 주종 설정',
              onPressed: onPressed,
            ),
          ],
        ),
        const SizedBox(height: ProfileLayoutSpacing.sectionToContent),
        // No panel: the chips sit on the page, each with its drink's own
        // colored picture, so a short list does not leave an empty box.
        if (selectedOptions.isEmpty)
          Text(
            '아직 설정된 관심 주종이 없어요.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final option in selectedOptions)
                _InterestChip(option: option),
            ],
          ),
      ],
    );
  }
}

class _InterestChip extends StatelessWidget {
  const _InterestChip({required this.option});
  final DrinkInterestOption option;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey<String>('profile-interest-${option.wireKey}'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.sm,
      AppSpacing.xs,
      AppSpacing.md,
      AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfacePrimary,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      border: Border.all(color: AppColors.profileInterestBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (option.assetPath case final path?)
          Image.asset(
            path,
            width: 26,
            height: 26,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          )
        else
          AppIcon(option.icon, size: 22, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          option.label,
          style: AppTextStyles.body.copyWith(
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}
