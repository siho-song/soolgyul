import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_surface.dart';

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
            TextSpan(text: '(선택)', style: AppTextStyles.supportBody),
          ],
        ),
        style: AppTextStyles.supportFieldLabel,
      ),
      const SizedBox(height: AppSpacing.sm),
      AppSurface(
        key: const ValueKey<String>('support-inquiry-images'),
        onPressed: onPick,
        semanticLabel: '첨부 이미지 선택',
        height: 70,
        variant: AppSurfaceVariant.outlined,
        borderRadius: AppRadii.control,
        borderColor: AppColors.borderControl,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (picking)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.photo_camera_outlined,
                size: 25,
                color: AppColors.supportIconWarm,
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$count/5',
              style: AppTextStyles.supportCounter.copyWith(
                color: AppColors.supportIconWarm,
              ),
            ),
          ],
        ),
      ),
      if (count > 0)
        TextButton(onPressed: onClear, child: const Text('첨부 이미지 선택 해제')),
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

class InquirySubmitButton extends StatelessWidget {
  const InquirySubmitButton({
    required this.onPressed,
    this.sending = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final bool sending;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '문의 보내기',
    child: Material(
      color: AppColors.supportButton,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 46,
          child: Center(
            child: Text(
              sending ? '문의 보내는 중…' : '문의 보내기',
              style: AppTextStyles.supportSubmit,
            ),
          ),
        ),
      ),
    ),
  );
}

InputDecoration inquiryFieldDecoration() => InputDecoration(
  filled: true,
  fillColor: AppColors.surfacePrimary,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: 14,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
    borderSide: const BorderSide(color: AppColors.borderControl),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
    borderSide: const BorderSide(color: AppColors.borderControl),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
    borderSide: const BorderSide(color: AppColors.actionPrimary, width: 1.6),
  ),
);
