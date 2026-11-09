import 'package:flutter/material.dart';
import '../data/account_deletion_gateway.dart';

/// Shown when a signed-in session belongs to an account awaiting deletion.
///
/// Signing in again restores the social provider link that the final purge
/// requires to be revoked, so the member either restores the account or
/// confirms the deletion again. Only an account whose link is still revoked
/// may simply sign out and wait for the purge.
class AccountRestoreDialog extends StatefulWidget {
  const AccountRestoreDialog({
    required this.gateway,
    required this.status,
    super.key,
  });
  final AccountDeletionGateway gateway;
  final AccountDeletionStatus status;
  @override
  State<AccountRestoreDialog> createState() => _AccountRestoreDialogState();
}

class _AccountRestoreDialogState extends State<AccountRestoreDialog> {
  bool _pending = false;
  String? _error;

  bool get _needsDeletionConfirmation =>
      !widget.status.providerRevoked && widget.status.state != 'purged';

  Future<void> _run(bool restore) async {
    setState(() {
      _pending = true;
      _error = null;
    });
    try {
      if (restore) {
        await widget.gateway.restore();
      } else {
        await widget.gateway.requestDeletion();
      }
      if (mounted) Navigator.of(context).pop(restore);
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
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('탈퇴 대기 중인 계정이에요'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.status.canRestore
                  ? '${date?.year}년 ${date?.month}월 ${date?.day}일 최종 삭제 전까지 계정을 복구할 수 있어요.'
                  : '복구 가능한 기간이 끝났어요. 계정 삭제 처리 중이에요.',
            ),
            if (_needsDeletionConfirmation)
              const Text(
                '다시 로그인하면서 소셜 연결이 되살아났어요. 탈퇴를 유지하려면 연결 해제를 다시 확인해야 해요.',
              ),
            if (_error != null)
              Text(_error!, key: const ValueKey('account-restore-error')),
          ],
        ),
        actions: [
          if (widget.status.canRestore)
            TextButton(
              key: const ValueKey('account-restore-confirm'),
              onPressed: _pending ? null : () => _run(true),
              child: const Text('계정 복구'),
            ),
          if (_needsDeletionConfirmation)
            TextButton(
              key: const ValueKey('account-keep-deletion'),
              onPressed: _pending ? null : () => _run(false),
              child: const Text('탈퇴 유지'),
            )
          else
            TextButton(
              onPressed: _pending
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('로그아웃'),
            ),
        ],
      ),
    );
  }
}
