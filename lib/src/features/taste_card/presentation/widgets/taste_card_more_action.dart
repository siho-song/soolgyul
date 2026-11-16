import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_top_bar.dart';
import '../../../records/data/record_note_gateway.dart';
import '../../../records/presentation/widgets/record_memo_editor.dart';
import '../../../records/presentation/widgets/record_price_editor.dart';

enum _MoreItem { note, price, delete }

/// 더보기 (⋮) at the right end of a saved record's card header. Its menu
/// offers the one-line note, as 메모 작성 or, once one is saved, 메모 보기, and
/// 삭제 for a card opened again from a list. A saved note opens in the same
/// balloon as a term's explanation, as the 취향 tab's record card shows it,
/// with 수정 for the note sheet. The note sheet stays open while its note is
/// stored: it closes once the note is saved, which a notice then says, and a
/// save that failed leaves it open with what was written. 구매 정보 남기기, or
/// 구매 정보 수정 once one is saved, opens the price sheet. Each saves on its
/// own; the card never changes. Only the app's records take a note or a
/// price; the web's first card neither.
class TasteCardMoreAction extends StatefulWidget {
  const TasteCardMoreAction({
    required this.recordId,
    this.noteGateway,
    this.onNoteSaved,
    this.recordMemo,
    this.recordPrice,
    this.onDelete,
    super.key,
  });

  final String recordId;

  /// The note's store; null, with no [recordMemo] either, leaves the note
  /// out of the menu.
  final RecordNoteGateway? noteGateway;

  /// Called after a changed note is stored, so lists showing it reload.
  final VoidCallback? onNoteSaved;

  /// The record's note, shared with the 한 줄 총평 of the card's tasting
  /// note; given, it is used in place of one made from [noteGateway].
  final RecordMemoEditor? recordMemo;

  /// The record's price, shared with the card's header line; null leaves
  /// the price out of the menu.
  final RecordPriceEditor? recordPrice;

  /// Deletes the record; null leaves 삭제 out of the menu.
  final VoidCallback? onDelete;

  @override
  State<TasteCardMoreAction> createState() => _TasteCardMoreActionState();
}

class _TasteCardMoreActionState extends State<TasteCardMoreAction> {
  /// The memo made here when the card hands none over.
  RecordMemoEditor? _ownMemo;
  bool _busy = false;

  RecordMemoEditor? get _memo => widget.recordMemo ?? _ownMemo;

  @override
  void initState() {
    super.initState();
    final gateway = widget.noteGateway;
    if (widget.recordMemo == null && gateway != null) {
      _ownMemo = RecordMemoEditor(
        recordId: widget.recordId,
        gateway: gateway,
        onSaved: () => widget.onNoteSaved?.call(),
      );
    }
  }

  @override
  void dispose() {
    _ownMemo?.dispose();
    super.dispose();
  }

  Future<void> _openMenu() async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final button = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final top = button.bottom - 6;
    final entries = <(_MoreItem, String)>[
      if (_memo case final memo?)
        (_MoreItem.note, memo.memo?.isNotEmpty == true ? '메모 보기' : '메모 남기기'),
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
      case _MoreItem.note:
        await _openNote();
      case _MoreItem.price:
        await widget.recordPrice?.edit(context);
      case _MoreItem.delete:
        widget.onDelete?.call();
      case null:
        break;
    }
  }

  Future<void> _openNote() async {
    final memo = _memo;
    if (memo == null || _busy) return;
    if (memo.memo == null) {
      setState(() => _busy = true);
      await memo.load();
      if (!mounted) return;
      setState(() => _busy = false);
    }
    await memo.open(context);
  }

  @override
  Widget build(BuildContext context) => AppTopBarMaterialAction(
    key: const ValueKey<String>('taste-card-more'),
    icon: Icons.more_vert_rounded,
    onPressed: _busy ? null : () => unawaited(_openMenu()),
    tooltip: '메뉴 더보기',
  );
}
