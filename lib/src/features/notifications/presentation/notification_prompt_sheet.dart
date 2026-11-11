import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/app_sheet.dart';

/// Asks the member whether the app may send its notifications, before the
/// phone asks. `true` when the member wants them; anything else is "not
/// now".
Future<bool?> showNotificationPromptSheet(BuildContext context) =>
    showAppSheet<bool>(
      context: context,
      builder: (_) => const NotificationPromptSheet(),
    );

class NotificationPromptSheet extends StatelessWidget {
  const NotificationPromptSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: appSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.surfaceSoft,
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                AppIconAsset.bell,
                size: 32,
                color: AppColors.actionPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            '오늘 마실 술,\n실패 없이 고르고 싶을 때',
            style: AppTextStyles.sectionTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '한 주를 마무리하는 기분 좋은 한 잔,\n'
            '실패하지 않도록 내 취향의 술을 챙겨드릴게요.',
            style: AppTextStyles.modalBody,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '혜택 및 추천 알림 수신에 동의해요',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            key: const ValueKey<String>('notification-prompt-accept'),
            label: '맞춤 알림 받기',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey<String>('notification-prompt-later'),
            label: '다음에 할게요',
            variant: AppButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    ),
  );
}
