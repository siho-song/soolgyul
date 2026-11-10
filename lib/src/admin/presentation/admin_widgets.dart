import 'package:flutter/material.dart';

import '../../design/app_tokens.dart';
import '../../design/app_typography.dart';
import '../admin_editorial_models.dart';
import '../../core/format/dates.dart';

/// `2026.08.18` in local time.
String adminDateLabel(DateTime value) => formatDotDate(value.toLocal());

Color adminStatusColor(AdminArticleStatus status) => switch (status) {
  AdminArticleStatus.draft => AppColors.textTertiary,
  AdminArticleStatus.published => AppColors.preferencePrimary,
  AdminArticleStatus.withdrawn => AppColors.actionDestructive,
};

/// A dot and the status name, tinted by status.
class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({required this.status, super.key});

  final AdminArticleStatus status;

  @override
  Widget build(BuildContext context) {
    final color = adminStatusColor(status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              status.label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A white card with a title row, used for every editor section.
class AdminSection extends StatelessWidget {
  const AdminSection({
    required this.title,
    required this.child,
    this.description,
    this.trailing,
    super.key,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfacePrimary,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.borderSubtle),
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppTextStyles.cardTitle),
                    if (description case final description?) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(description, style: AppTextStyles.caption),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    ),
  );
}
