import 'package:flutter/material.dart';

import '../../../../core/errors/error_report.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_dialog.dart';

/// Asks before a saved card is deleted, and stays up while it is deleted:
/// 삭제 turns into a spinner until [onDelete] has finished, so the reader
/// sees the tap was taken and has nothing to tap twice. The popup then
/// closes by itself; [onDelete] reports its own outcome. One that throws
/// leaves the popup up to try again or cancel.
class RecordDeleteDialog extends StatefulWidget {
  const RecordDeleteDialog({required this.onDelete, super.key});

  final Future<void> Function() onDelete;

  @override
  State<RecordDeleteDialog> createState() => _RecordDeleteDialogState();
}

class _RecordDeleteDialogState extends State<RecordDeleteDialog> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.onDelete();
    } catch (error, stack) {
      reportError(error, stack, where: 'card delete');
      if (mounted) setState(() => _deleting = false);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AppDialogBody(
    title: '술결 기록을 삭제할까요?',
    body: '삭제된 술결 카드와 메모는 되돌릴 수 없어요.',
    actions: <Widget>[
      AppButton(
        key: const ValueKey<String>('record-delete-cancel'),
        label: '취소',
        variant: AppButtonVariant.neutral,
        size: AppButtonSize.popup,
        isDisabled: _deleting,
        onPressed: () => Navigator.of(context).pop(),
      ),
      AppButton(
        key: const ValueKey<String>('record-delete-confirm'),
        label: '삭제',
        size: AppButtonSize.popup,
        isLoading: _deleting,
        onPressed: _delete,
      ),
    ],
  );
}
