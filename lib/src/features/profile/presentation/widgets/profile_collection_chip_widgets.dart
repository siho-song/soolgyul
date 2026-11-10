import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';

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
