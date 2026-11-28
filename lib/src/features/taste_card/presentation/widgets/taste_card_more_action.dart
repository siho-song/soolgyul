import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_top_bar.dart';

enum _MoreItem { edit, delete }

/// 더보기 (⋮) at the right end of a saved card's header in the app. Its menu
/// offers 수정 and 삭제, each where it applies; a header with neither does
/// not draw it.
class TasteCardMoreAction extends StatelessWidget {
  const TasteCardMoreAction({this.onEdit, this.onDelete, super.key})
    : assert(onEdit != null || onDelete != null, 'a menu with nothing in it');

  /// 수정: turns the card to its 테이스팅 노트; null leaves it out.
  final VoidCallback? onEdit;

  /// 삭제, which asks first; null leaves it out.
  final VoidCallback? onDelete;

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final button = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final top = button.bottom - 6;
    final entries = <(_MoreItem, String)>[
      if (onEdit != null) (_MoreItem.edit, '수정'),
      if (onDelete != null) (_MoreItem.delete, '삭제'),
    ];
    final item = await showMenu<_MoreItem>(
      context: context,
      // Right-aligned under the ⋮ glyph, whose right edge sits 10 points in
      // from the button's.
      position: RelativeRect.fromLTRB(
        button.left,
        top,
        overlay.size.width - button.right + 10,
        overlay.size.height - top,
      ),
      color: AppColors.surfaceCanvas,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: const BorderSide(color: AppColors.borderSubtle),
      ),
      items: <PopupMenuEntry<_MoreItem>>[
        for (final (index, (item, label)) in entries.indexed) ...[
          if (index > 0)
            const PopupMenuDivider(height: 1, color: AppColors.borderSubtle),
          PopupMenuItem<_MoreItem>(
            key: ValueKey<String>('taste-card-menu-${item.name}'),
            value: item,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Center(
              child: Text(
                label,
                style: item == _MoreItem.delete
                    ? AppTextStyles.menuItemTitle.copyWith(
                        color: AppColors.actionDestructive,
                      )
                    : AppTextStyles.menuItemTitle,
              ),
            ),
          ),
        ],
      ],
    );
    switch (item) {
      case _MoreItem.edit:
        onEdit?.call();
      case _MoreItem.delete:
        onDelete?.call();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => AppTopBarMaterialAction(
    key: const ValueKey<String>('taste-card-more'),
    icon: Icons.more_vert_rounded,
    onPressed: () => unawaited(_openMenu(context)),
    tooltip: '메뉴 더보기',
  );
}
