import 'package:flutter/material.dart';

import '../../../../design/app_tokens.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_sheet.dart';

/// Asks before a saved card is deleted, and stays up while it is deleted:
/// 삭제 turns into a spinner until [onDelete] has finished, so the reader
/// sees the tap was taken and has nothing to tap twice. The sheet then
/// closes by itself; [onDelete] reports its own outcome.
class RecordDeleteSheet extends StatefulWidget {
  const RecordDeleteSheet({required this.onDelete, super.key});

  final Future<void> Function() onDelete;

  @override
  State<RecordDeleteSheet> createState() => _RecordDeleteSheetState();
}

class _RecordDeleteSheetState extends State<RecordDeleteSheet> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    await widget.onDelete();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AppSheetBody(
    title: '술결 기록을 삭제할까요?',
    body: '삭제된 술결 카드와 메모는 되돌릴 수 없어요.',
    children: <Widget>[
      AppButton(
        key: const ValueKey<String>('record-delete-confirm'),
        label: '삭제',
        variant: AppButtonVariant.destructive,
        isLoading: _deleting,
        onPressed: _delete,
      ),
      const SizedBox(height: AppSpacing.sm),
      AppButton(
        key: const ValueKey<String>('record-delete-cancel'),
        label: '취소',
        variant: AppButtonVariant.tertiary,
        isDisabled: _deleting,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}
