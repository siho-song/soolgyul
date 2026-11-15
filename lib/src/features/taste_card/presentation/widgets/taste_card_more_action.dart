import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../design/app_typography.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_term_tooltip.dart';
import '../../../../widgets/app_text_field.dart';
import '../../../../widgets/app_top_bar.dart';
import '../../../records/data/record_note_gateway.dart';
import '../../../records/presentation/widgets/record_price_editor.dart';
import '../../../../widgets/app_sheet.dart';
import '../../../../widgets/app_snack_bar.dart';

enum _MoreItem { note, price, delete }

/// 더보기 (⋮) at the right end of a saved record's card header. Its menu
/// offers the one-line note, as 메모 작성 or, once one is saved, 메모 보기, and
/// 삭제 for a card opened again from a list. A saved note opens in the same
/// balloon as a term's explanation, as the 취향 tab's record card shows it,
/// with 수정 for the note sheet. The note sheet stays open while its note is
/// stored: it closes once the note is saved, which a notice then says, and a
/// save that failed leaves it open with what was written. 구입 가격 남기기, or
/// 구입 가격 수정 once one is saved, opens the price sheet. Each saves on its
/// own; the card never changes. Only the app's records take a note or a
/// price; the web's first card neither.
class TasteCardMoreAction extends StatefulWidget {
  const TasteCardMoreAction({
    required this.recordId,
    this.noteGateway,
    this.onNoteSaved,
    this.recordPrice,
    this.onDelete,
    super.key,
  });

  final String recordId;

  /// The note's store; null leaves the note out of the menu.
  final RecordNoteGateway? noteGateway;

  /// Called after a changed note is stored, so lists showing it reload.
  final VoidCallback? onNoteSaved;

  /// The record's price, shared with the card's header line; null leaves
  /// the price out of the menu.
  final RecordPriceEditor? recordPrice;

  /// Deletes the record; null leaves 삭제 out of the menu.
  final VoidCallback? onDelete;

  @override
  State<TasteCardMoreAction> createState() => _TasteCardMoreActionState();
}

class _TasteCardMoreActionState extends State<TasteCardMoreAction> {
  /// The stored note; null until it has been read.
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.noteGateway != null) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final note = (await widget.noteGateway!.loadNote(widget.recordId)).trim();
      if (mounted) setState(() => _note = note);
    } catch (_) {
      // Choosing the note reads it again.
    }
  }

  Future<void> _openMenu() async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final button = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final top = button.bottom - 6;
    final entries = <(_MoreItem, String)>[
      if (widget.noteGateway != null)
        (_MoreItem.note, _note?.isNotEmpty == true ? '메모 보기' : '메모 남기기'),
      if (widget.recordPrice case final price?)
        (_MoreItem.price, price.price == null ? '구입 가격 남기기' : '구입 가격 수정'),
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
    if (_busy) return;
    if (_note == null) {
      setState(() => _busy = true);
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
    }
    final note = _note;
    if (note == null) {
      _tell('메모를 불러오지 못했어요. 다시 시도해 주세요.');
    } else if (note.isEmpty) {
      await _editNote();
    } else {
      await showTermTooltip(
        context,
        title: '남긴 메모',
        text: note,
        actionLabel: '메모 수정',
        onAction: () => unawaited(_editNote()),
      );
    }
  }

  Future<void> _editNote() async {
    if (widget.noteGateway == null || _busy || !mounted) return;
    var sheetOpen = true;
    await showAppSheet<void>(
      context: context,
      builder: (context) => _NoteSheet(
        initial: _note ?? '',
        onSave: (note) async {
          final failure = await _saveNote(note);
          // A sheet closed while its note was on the way cannot say so.
          if (failure != null && !sheetOpen && mounted) _tell(failure);
          return failure;
        },
      ),
    );
    sheetOpen = false;
  }

  /// Stores [note] and says it was saved; an unchanged note is not sent.
  /// Returns what went wrong, or null.
  Future<String?> _saveNote(String note) async {
    final trimmed = note.trim();
    if (trimmed == (_note ?? '')) return null;
    try {
      await widget.noteGateway!.saveNote(recordId: widget.recordId, note: note);
    } on RecordNoteException catch (error) {
      return error.message;
    } catch (_) {
      return '메모를 저장하지 못했어요. 다시 시도해 주세요.';
    }
    if (!mounted) return null;
    setState(() => _note = trimmed);
    widget.onNoteSaved?.call();
    showAppSnackBar(
      context,
      trimmed.isEmpty ? '메모를 지웠어요.' : '메모를 저장했어요.',
      success: true,
    );
    return null;
  }

  void _tell(String message) {
    showAppSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) => AppTopBarMaterialAction(
    key: const ValueKey<String>('taste-card-more'),
    icon: Icons.more_vert_rounded,
    onPressed: _busy ? null : () => unawaited(_openMenu()),
    tooltip: '메뉴 더보기',
  );
}

/// The note sheet stores the note itself and closes once [onSave] went
/// through. A save that failed keeps it open, what was written still in the
/// field, with the reason under it.
class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.initial, required this.onSave});
  final String initial;

  /// Stores the note; answers what went wrong, or null once it is saved.
  final Future<String?> Function(String note) onSave;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> with FocusWhenSheetOpens {
  late final _controller = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _failure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    final failure = await widget.onSave(_controller.text);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: appSheetPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AppSheetHeading(title: '한 줄 메모'),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            key: const ValueKey<String>('taste-card-note-field'),
            controller: _controller,
            focusNode: sheetFocus,
            minLines: 1,
            maxLines: 3,
            // The server keeps at most this many characters.
            maxLength: 2000,
            hintText: '예) 첫맛은 강렬했는데 은은한 단맛이 남아 좋았어요.',
            hasError: _failure != null,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_failure != null) setState(() => _failure = null);
            },
            onFieldSubmitted: (_) => unawaited(_save()),
          ),
          if (_failure case final failure?) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              failure,
              key: const ValueKey<String>('taste-card-note-failure'),
              style: AppTextStyles.body.copyWith(
                color: AppColors.actionPrimary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            key: const ValueKey<String>('taste-card-note-save'),
            label: '완료',
            onPressed: () => unawaited(_save()),
            isLoading: _saving,
            variant: AppButtonVariant.accent,
            size: AppButtonSize.sheet,
          ),
        ],
      ),
    );
  }
}
