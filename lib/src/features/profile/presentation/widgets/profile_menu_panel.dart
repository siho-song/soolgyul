import 'package:flutter/material.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_icon.dart';
import '../../../../widgets/app_list_row.dart';
import '../../../../widgets/app_surface.dart';

class ProfileMenuPanel extends StatelessWidget {
  const ProfileMenuPanel({super.key, required this.items});

  final List<ProfileMenuItem> items;

  @override
  Widget build(BuildContext context) => AppPanel(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    child: Column(
      children: <Widget>[
        for (var index = 0; index < items.length; index++)
          _ProfileMenuRow(item: items[index], last: index == items.length - 1),
      ],
    ),
  );
}

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({required this.item, required this.last});

  final ProfileMenuItem item;
  final bool last;

  @override
  Widget build(BuildContext context) => AppListRow(
    title: item.title,
    leading: CircleAvatar(
      radius: 17,
      backgroundColor: AppColors.surfaceSoft,
      child: Icon(
        item.materialIcon,
        size: 20,
        color: AppColors.actionPrimaryStrong,
      ),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (item.count != null) ...<Widget>[
          Text(
            item.count!,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        const AppIcon(
          AppIconAsset.next,
          size: 20,
          color: AppColors.textTertiary,
        ),
      ],
    ),
    onPressed: item.onPressed,
    density: AppListRowDensity.compact,
    inset: AppListRowInset.none,
    showDivider: !last,
  );
}

class ProfileMenuItem {
  const ProfileMenuItem({
    required this.title,
    required this.onPressed,
    required this.materialIcon,
    this.count,
  });

  final IconData materialIcon;
  final String title;
  final String? count;
  final VoidCallback onPressed;
}
