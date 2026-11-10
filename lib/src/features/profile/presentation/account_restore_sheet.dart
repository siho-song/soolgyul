import 'package:flutter/material.dart';

import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_sheet.dart';
import '../data/account_deletion_gateway.dart';

/// Shown when a signed-in session belongs to an account awaiting deletion.
///
/// Signing in again restores the social provider link that the final purge
/// requires to be revoked, so the member either restores the account or
/// confirms the deletion again. Only an account whose link is still revoked
/// may simply sign out and wait for the purge.
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
      child: AppSheetBody(
        hasHandle: false,
        title: '탈퇴 대기 중인 계정이에요',
        body: <String>[
          widget.status.canRestore
              ? '${date?.year}년 ${date?.month}월 ${date?.day}일 최종 삭제 전까지 계정을 복구할 수 있어요.'
              : '복구 가능한 기간이 끝났어요. 계정 삭제 처리 중이에요.',
          if (_needsDeletionConfirmation)
            '다시 로그인하면서 소셜 연결이 되살아났어요. 탈퇴 유지를 누르면 연결을 다시 해제해요.',
        ].join('\n\n'),
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
          if (widget.status.canRestore) ...<Widget>[
            AppButton(
              key: const ValueKey('account-restore-confirm'),
              label: '계정 복구',
              isDisabled: _pending,
              onPressed: () => _run(true),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_needsDeletionConfirmation)
            AppButton(
              key: const ValueKey('account-keep-deletion'),
              label: '탈퇴 유지',
              variant: AppButtonVariant.tertiary,
              isDisabled: _pending,
              onPressed: () => _run(false),
            )
          else
            AppButton(
              label: '로그아웃',
              variant: AppButtonVariant.tertiary,
              isDisabled: _pending,
              onPressed: () => Navigator.of(context).pop(false),
            ),
        ],
      ),
    );
  }
}
