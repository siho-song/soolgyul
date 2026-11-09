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
      17,
      AppSpacing.sm,
      17,
      AppSpacing.massive,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSurface(
          key: const ValueKey<String>('support-faq-entry'),
          onPressed: () => openLegalDocument(context, LegalDocument.faq),
          semanticLabel: '자주 묻는 질문 열기',
          variant: AppSurfaceVariant.card,
          borderRadius: AppRadii.compactCard,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: const Row(
            children: <Widget>[
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.supportIconSurface,
                child: Icon(
                  Icons.quiz_outlined,
                  size: 27,
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
                      '술결 이용 중 자주 받는 질문과\n답변을 웹에서 확인할 수 있어요.',
                      style: AppTextStyles.supportBody,
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              AppIcon(
                AppIconAsset.next,
                color: AppColors.supportSecondary,
                size: 20,
                weight: AppIconWeight.strong,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('문의하기', style: AppTextStyles.supportSectionTitle),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                '오류나 불편한 점, 서비스에 대한 의견을 보내주세요.',
                style: AppTextStyles.supportBody,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppSurface(
          key: const ValueKey<String>('support-inquiry-entry'),
          onPressed: onInquiry,
          semanticLabel: '문의 작성 화면 열기',
          variant: AppSurfaceVariant.card,
          borderRadius: AppRadii.compactCard,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.supportIconSurface,
                child: Icon(
                  Icons.mail_outline_rounded,
                  size: 29,
                  color: AppColors.headerTitle,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('문의하기', style: AppTextStyles.supportCardTitle),
                    SizedBox(height: AppSpacing.xs),
                    Text(
                      '문의 유형을 선택하고 내용을\n남겨주시면 확인 후 답변드려요.',
                      style: AppTextStyles.supportBody,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const AppIcon(
                AppIconAsset.next,
                color: AppColors.supportSecondary,
                size: 20,
                weight: AppIconWeight.strong,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
