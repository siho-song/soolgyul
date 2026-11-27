import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_top_bar.dart';
import '../../../profile/data/liked_cards_gateway.dart';
import '../../../../widgets/app_snack_bar.dart';

enum _MoreItem { save, edit, delete }

/// 더보기 (⋮) at the right end of a saved card's header in the app. Its menu
/// offers 저장 (저장 취소 once kept), 수정 and 삭제, each where it applies.
/// 저장 keeps the card in 보관한 술결 카드; the server takes it before the
/// menu says so.
class TasteCardMoreAction extends StatefulWidget {
  const TasteCardMoreAction({
    required this.cardId,
    this.gateway,
    this.isActive = true,
    this.onChanged,
    this.onEdit,
    this.onDelete,
    super.key,
  });
  final String cardId;

  /// Where 저장 is kept; null leaves 저장 out.
  final LikedCardsGateway? gateway;

  /// 수정: turns the card to its 테이스팅 노트; null leaves it out.
  final VoidCallback? onEdit;

  /// 삭제, which asks first; null leaves it out.
  final VoidCallback? onDelete;
  final bool isActive;

  /// Called after the server took a like or an unlike.
  final VoidCallback? onChanged;

  @override
  State<TasteCardMoreAction> createState() => _TasteCardMoreActionState();
}

class _TasteCardMoreActionState extends State<TasteCardMoreAction> {
  bool? _liked;
  bool _busy = false;
  bool _loadFailed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive && widget.gateway != null) unawaited(_load());
  }

  @override
  void didUpdateWidget(TasteCardMoreAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cardId != oldWidget.cardId ||
        widget.gateway != oldWidget.gateway ||
        widget.isActive != oldWidget.isActive) {
      _request++;
      _liked = null;
      _loadFailed = false;
      _busy = false;
      if (widget.isActive && widget.gateway != null) unawaited(_load());
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _loadFailed = false;
    });
    try {
      final liked = await widget.gateway!.isLiked(widget.cardId);
      if (mounted && request == _request) setState(() => _liked = liked);
    } catch (_) {
      if (mounted && request == _request) setState(() => _loadFailed = true);
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy || _liked == null) return;
    final request = ++_request;
    final next = !_liked!;
    setState(() => _busy = true);
    try {
      if (next) {
        await widget.gateway!.like(widget.cardId);
      } else {
        await widget.gateway!.unlike(widget.cardId);
      }
      widget.onChanged?.call();
      if (mounted && request == _request) {
        setState(() => _liked = next);
        if (next) {
          showAppSnackBar(
            context,
            '보관한 술결 카드에 담았어요. 내 정보에서 다시 볼 수 있어요.',
            success: true,
          );
        } else {
          hideAppSnackBar(context);
        }
      }
    } catch (error) {
      if (mounted && request == _request) {
        // In the menu's own words: 저장 failed, or 저장 취소 did.
        showAppSnackBar(
          context,
          failureLine(
            error,
            next ? '저장하지 못했어요. 다시 시도해 주세요.' : '저장을 취소하지 못했어요. 다시 시도해 주세요.',
          ),
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _openMenu() async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final button = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final top = button.bottom - 6;
    final canSave = widget.isActive && !_busy && _liked != null;
    final entries = <(_MoreItem, String)>[
      if (widget.gateway != null)
        (_MoreItem.save, _liked == true ? '저장 취소' : '저장'),
      if (widget.onEdit != null) (_MoreItem.edit, '수정'),
      if (widget.onDelete != null) (_MoreItem.delete, '삭제'),
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
            enabled: item != _MoreItem.save || canSave || _loadFailed,
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
      case _MoreItem.save:
        await (_loadFailed ? _load() : _toggle());
      case _MoreItem.edit:
        widget.onEdit?.call();
      case _MoreItem.delete:
        widget.onDelete?.call();
      case null:
        break;
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
