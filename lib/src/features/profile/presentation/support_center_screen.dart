import 'package:flutter/material.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_surface.dart';
import 'legal_document_link.dart';

class SupportCenterScreen extends StatelessWidget {
  const SupportCenterScreen({required this.onInquiry, super.key});

  final VoidCallback onInquiry;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.massive,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSurface(
          key: const ValueKey<String>('support-faq-entry'),
          onPressed: () => openLegalDocument(context, LegalDocument.faq),
          semanticLabel: '자주 묻는 질문 보기',
          variant: AppSurfaceVariant.card,
          borderRadius: AppRadii.compactCard,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: const Row(
            children: <Widget>[
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.surfaceSoft,
                child: Icon(
                  Icons.quiz_outlined,
                  size: AppSizes.iconXl,
                  color: AppColors.headerTitle,
                ),
              ),
              SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('자주 묻는 질문', style: AppTextStyles.supportCardTitle),
                    SizedBox(height: AppSpacing.xs),
                    Text(
                      '서비스 이용에 대해 자주 묻는 질문과\n답변을 확인해 보세요.',
                      style: AppTextStyles.detail,
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              AppIcon(
                AppIconAsset.next,
                color: AppColors.textSecondary,
                size: AppSizes.iconMd,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('1:1 문의', style: AppTextStyles.supportSectionTitle),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                '불편한 점이나 전하고 싶은 의견을 자유롭게 남겨주세요.',
                style: AppTextStyles.detail,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppSurface(
          key: const ValueKey<String>('support-inquiry-entry'),
          onPressed: onInquiry,
          semanticLabel: '문의 작성하기',
          variant: AppSurfaceVariant.card,
          borderRadius: AppRadii.compactCard,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.surfaceSoft,
                child: Icon(
                  Icons.mail_outline_rounded,
                  size: AppSizes.iconXl,
                  color: AppColors.headerTitle,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('1:1 문의', style: AppTextStyles.supportCardTitle),
                    SizedBox(height: AppSpacing.xs),
                    Text(
                      '문의 유형을 선택하고 내용을 남겨주시면\n확인 후 빠르게 답변해 드릴게요.',
                      style: AppTextStyles.detail,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const AppIcon(
                AppIconAsset.next,
                color: AppColors.textSecondary,
                size: AppSizes.iconMd,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
