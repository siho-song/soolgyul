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

/// Why 발행 is greyed out on a post without photos: the explore tab shows a
/// post by its cover.
const adminPublishNeedsPhoto = '사진을 한 장 이상 올려야 발행할 수 있어요.';

/// Asks before a post goes up on the explore tab or comes down from it.
/// [savesEdits] says that edits not saved yet go up with it.
Future<bool> confirmArticleStatus(
  BuildContext context,
  AdminArticleStatus status, {
  bool savesEdits = false,
}) async {
  final publishing = status == AdminArticleStatus.published;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(publishing ? '발행할까요?' : '철회할까요?'),
      content: Text(
        !publishing
            ? '앱에서 바로 내려가요. 다시 발행하면 다시 보여요.'
            : savesEdits
            ? '저장하지 않은 변경도 함께 저장되고, 앱의 탐색 탭에 바로 보여요.'
            : '앱의 탐색 탭에 바로 보여요.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const ValueKey<String>('admin-confirm-status'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(publishing ? '발행' : '철회'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Asks before leaving the editor with changes not saved.
Future<bool> confirmDiscardEdits(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('저장하지 않은 변경이 있어요'),
      content: const Text('나가면 바꾼 내용이 사라져요.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('계속 편집'),
        ),
        FilledButton(
          key: const ValueKey<String>('admin-discard-edits'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('나가기'),
        ),
      ],
    ),
  );
  return leave == true;
}

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
