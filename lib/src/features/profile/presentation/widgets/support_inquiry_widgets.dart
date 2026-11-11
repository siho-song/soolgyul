import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_surface.dart';
import '../../../../widgets/app_state_view.dart';

class InquiryAttachments extends StatelessWidget {
  const InquiryAttachments({
    super.key,
    required this.count,
    required this.picking,
    required this.onPick,
    required this.onClear,
  });
  final int count;
  final bool picking;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: '첨부 이미지 '),
            TextSpan(text: '(선택)', style: AppTextStyles.detail),
          ],
        ),
        style: AppTextStyles.supportFieldLabel,
      ),
      const SizedBox(height: AppSpacing.sm),
      AppSurface(
        key: const ValueKey<String>('support-inquiry-images'),
        onPressed: onPick,
        semanticLabel: '사진 첨부하기',
        height: 70,
        variant: AppSurfaceVariant.outlined,
        borderRadius: AppRadii.control,
        borderColor: AppColors.borderSubtle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (picking)
              const AppSmallSpinner()
            else
              const Icon(
                Icons.photo_camera_outlined,
                size: AppSizes.iconLg,
                color: AppColors.supportIconWarm,
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$count/5',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.supportIconWarm,
              ),
            ),
          ],
        ),
      ),
      if (count > 0) TextButton(onPressed: onClear, child: const Text('첨부 취소')),
    ],
  );
}

class InquiryFieldLabel extends StatelessWidget {
  const InquiryFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTextStyles.supportFieldLabel);
}

InputDecoration inquiryFieldDecoration() => InputDecoration(
  filled: true,
  fillColor: AppColors.surfacePrimary,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.s14,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
    borderSide: const BorderSide(color: AppColors.borderSubtle),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
    borderSide: const BorderSide(color: AppColors.borderSubtle),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
    borderSide: const BorderSide(color: AppColors.actionPrimary, width: 1.6),
  ),
);
