import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';

/// 저장 콘텐츠 화면에서 공통으로 사용하는 주종 필터 칩입니다.
class ProfileCollectionFilterChip extends StatelessWidget {
  const ProfileCollectionFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.actionPrimary : AppColors.collectionChipSurface,
    shape: StadiumBorder(
      side: BorderSide(
        color: selected
            ? AppColors.actionPrimary
            : AppColors.collectionChipBorder,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 10,
            color: selected
                ? AppColors.textOnPrimary
                : AppColors.collectionChipText,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

/// Empty result of a saved collection under the selected filter.
class ProfileCollectionEmptyState extends StatelessWidget {
  const ProfileCollectionEmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
    child: Column(
      children: <Widget>[
        Icon(icon, size: 34, color: AppColors.textTertiary),
        const SizedBox(height: AppSpacing.md),
        Text(message, style: AppTextStyles.bodySmall),
      ],
    ),
  );
}
