import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_top_bar.dart';
import '../../../records/presentation/widgets/record_memo_editor.dart';
import '../../../records/presentation/widgets/record_price_editor.dart';
import 'taste_card_note_opener.dart';

enum _MoreItem { overall, price, delete }

/// 더보기 (⋮) at the right end of a saved record's card header. Its menu
/// offers 총평 and 구매 정보, each to write or to change, and 삭제 for a
/// card opened again from a list. 총평 and 구매 정보 are written on the
/// card's 테이스팅 노트: with a [noteOpener] the card turns to that tab and
/// opens the sheet there; without one the sheet opens where the card is.
/// Only the app's records take a note or a price; the web's first card
/// neither.
class TasteCardMoreAction extends StatefulWidget {
  const TasteCardMoreAction({
    required this.recordId,
    this.recordMemo,
    this.recordPrice,
    this.noteOpener,
    this.onDelete,
    super.key,
  });

  final String recordId;

  /// The record's 총평; null leaves it out of the menu.
  final RecordMemoEditor? recordMemo;

  /// The record's price, shared with the card's header line; null leaves
  /// the price out of the menu.
  final RecordPriceEditor? recordPrice;

  /// Turns the card below to its 테이스팅 노트 to write there.
  final TasteCardNoteOpener? noteOpener;

  /// Deletes the record; null leaves 삭제 out of the menu.
  final VoidCallback? onDelete;

  @override
  State<TasteCardMoreAction> createState() => _TasteCardMoreActionState();
}

class _TasteCardMoreActionState extends State<TasteCardMoreAction> {
  Future<void> _openMenu() async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final button = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final top = button.bottom - 6;
    final entries = <(_MoreItem, String)>[
      if (widget.recordMemo case final memo?)
        (_MoreItem.overall, memo.memo?.isNotEmpty == true ? '총평 수정' : '총평 남기기'),
      if (widget.recordPrice case final price?)
        (_MoreItem.price, price.price == null ? '구매 정보 남기기' : '구매 정보 수정'),
      if (widget.onDelete != null) (_MoreItem.delete, '카드 삭제'),
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
          // The menu is at least 112 wide; a centred label keeps its left
          // and right space even.
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
    if (!mounted) return;
    switch (item) {
      case _MoreItem.overall:
        _write(TasteCardNoteSlot.overall);
      case _MoreItem.price:
        _write(TasteCardNoteSlot.price);
      case _MoreItem.delete:
        widget.onDelete?.call();
      case null:
        break;
    }
  }

  void _write(TasteCardNoteSlot slot) {
    if (widget.noteOpener case final opener?) {
      opener.open(slot);
      return;
    }
    switch (slot) {
      case TasteCardNoteSlot.overall:
        unawaited(widget.recordMemo?.edit(context, title: '총평'));
      case TasteCardNoteSlot.price:
        unawaited(widget.recordPrice?.edit(context));
    }
  }

  @override
  Widget build(BuildContext context) => AppTopBarMaterialAction(
    key: const ValueKey<String>('taste-card-more'),
    icon: Icons.more_vert_rounded,
    onPressed: () => unawaited(_openMenu()),
    tooltip: '메뉴 더보기',
  );
}
