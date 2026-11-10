import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_sheet.dart';
import '../data/account_deletion_gateway.dart';

/// Shown when a signed-in session belongs to an account awaiting deletion.
///
/// Within the 30 days the member restores the account or keeps the
/// deletion; after them the sheet only says the deletion is being finished.
/// Either way it tells when the account goes and that signing up again is
/// possible afterwards. Keeping the deletion just signs out: the server
/// deletes the account on its day.
class AccountRestoreSheet extends StatefulWidget {
  const AccountRestoreSheet({
    required this.gateway,
    required this.status,
    super.key,
  });
  final AccountDeletionGateway gateway;
  final AccountDeletionStatus status;
  @override
  State<AccountRestoreSheet> createState() => _AccountRestoreSheetState();
}

class _AccountRestoreSheetState extends State<AccountRestoreSheet> {
  bool _pending = false;
  String? _error;

  Future<void> _restore() async {
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      await widget.gateway.restore();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AccountDeletionException
              ? error.message
              : '처리하지 못했어요. 다시 시도해주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.status.deadline?.toLocal();
    final canRestore = widget.status.canRestore;
    return PopScope(
      canPop: false,
      child: AppSheetBody(
        hasHandle: false,
        title: canRestore ? '탈퇴 대기 중인 계정이에요' : '계정을 삭제하고 있어요',
        body: canRestore
            ? '${date?.year}년 ${date?.month}월 ${date?.day}일에 계정이 삭제돼요. '
                  '그 전까지는 계정을 복구할 수 있어요.\n\n'
                  '탈퇴를 유지하면 삭제가 끝난 뒤에 다시 가입할 수 있어요.'
            : '복구할 수 있는 기간이 끝났어요.\n\n'
                  '삭제는 보통 1시간 안에 끝나고, 그 뒤에 다시 가입할 수 있어요.',
        children: <Widget>[
          if (_error != null) ...<Widget>[
            Text(
              _error!,
              key: const ValueKey('account-restore-error'),
              style: AppTextStyles.caption.copyWith(
                color: AppColors.actionDestructive,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (canRestore) ...<Widget>[
            AppButton(
              key: const ValueKey('account-restore-confirm'),
              label: '계정 복구',
              isDisabled: _pending,
              onPressed: _restore,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          AppButton(
            key: const ValueKey('account-keep-deletion'),
            label: canRestore ? '탈퇴 유지' : '확인',
            variant: canRestore
                ? AppButtonVariant.tertiary
                : AppButtonVariant.primary,
            isDisabled: _pending,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
