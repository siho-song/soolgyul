import 'package:flutter/material.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_list_row.dart';
import '../../../widgets/app_surface.dart';
import '../../notifications/data/notification_access.dart';
import '../../notifications/data/notification_prompt_memory.dart';
import '../../notifications/presentation/widgets/notification_setting_row.dart';
import '../data/marketing_consent_gateway.dart';
import '../data/account_deletion_gateway.dart';
import 'widgets/marketing_consent_control.dart';
import 'legal_document_link.dart';
import '../../../widgets/app_snack_bar.dart';
import '../../../widgets/app_state_view.dart';
import '../../../core/errors/error_report.dart';

class PolicyScreen extends StatefulWidget {
  const PolicyScreen({
    required this.onSignOut,
    this.onRequestAccountDeletion,
    this.marketingConsentGateway,
    this.notificationAccess,
    this.notificationPromptMemory,
    this.isActive = true,
    super.key,
  });

  final Future<void> Function() onSignOut;
  final Future<void> Function()? onRequestAccountDeletion;
  final MarketingConsentGateway? marketingConsentGateway;

  /// `null` hides the row that turns notifications on and off.
  final NotificationAccess? notificationAccess;
  final NotificationPromptMemory? notificationPromptMemory;
  final bool isActive;

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
  bool _signOutPending = false;
  bool _deletionPending = false;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenX,
      AppSpacing.sm,
      AppSpacing.screenX,
      AppSpacing.massive,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppPanel(
          key: const ValueKey<String>('policy-documents-panel'),
          padding: _panelPadding,
          child: Column(
            children: <Widget>[
              _PolicyDocumentRow(
                title: '서비스 이용약관',
                showDivider: true,
                onPressed: () =>
                    openLegalDocument(context, LegalDocument.terms),
              ),
              _PolicyDocumentRow(
                title: '개인정보 처리방침',
                onPressed: () =>
                    openLegalDocument(context, LegalDocument.privacy),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        const Text('알림 및 수신 설정', style: AppTextStyles.cardTitle),
        const SizedBox(height: AppSpacing.md),
        AppPanel(
          key: const ValueKey<String>('policy-marketing-panel'),
          padding: _panelPadding,
          child: Column(
            children: <Widget>[
              if (widget.notificationAccess case final access?) ...<Widget>[
                NotificationSettingRow(
                  access: access,
                  memory: widget.notificationPromptMemory,
                  isActive: widget.isActive,
                ),
                const Divider(
                  height: 1,
                  indent: AppSpacing.s10,
                  endIndent: AppSpacing.s10,
                  color: AppColors.borderSubtle,
                ),
              ],
              SizedBox(
                height: AppSizes.menuRowHeight,
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '광고성 정보 수신 동의',
                        style: AppTextStyles.menuItemTitle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    MarketingConsentControl(
                      gateway: widget.marketingConsentGateway,
                      isActive: widget.isActive,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        const Text('계정 관리', style: AppTextStyles.cardTitle),
        const SizedBox(height: AppSpacing.md),
        AppPanel(
          key: const ValueKey<String>('policy-account-panel'),
          padding: _panelPadding,
          child: Column(
            children: <Widget>[
              AppListRow(
                key: const ValueKey<String>('policy-sign-out'),
                title: '로그아웃',
                onPressed: _signOutPending || _deletionPending
                    ? null
                    : _confirmSignOut,
                // The row turns while the request is on its way.
                trailing: _signOutPending ? _busy('로그아웃하는 중') : null,
                density: AppListRowDensity.compact,
                inset: AppListRowInset.none,
                showDivider: true,
              ),
              AppListRow(
                key: const ValueKey<String>('policy-account-deletion'),
                title: '계정 삭제',
                onPressed: _deletionPending || _signOutPending
                    ? null
                    : _showAccountDeletion,
                trailing: _deletionPending ? _busy('계정 삭제를 요청하는 중') : null,
                density: AppListRowDensity.compact,
                inset: AppListRowInset.none,
                showDivider: false,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _busy(String label) => AppSmallSpinner(semanticsLabel: label);

  Future<void> _confirmSignOut() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialogBody(
        title: '로그아웃 확인',
        body: '로그인 상태가 해제돼요.',
        actions: <Widget>[
          AppButton(
            label: '취소',
            variant: AppButtonVariant.neutral,
            size: AppButtonSize.popup,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            key: const ValueKey<String>('policy-sign-out-confirm'),
            label: '확인',
            size: AppButtonSize.popup,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _signOutPending = true);
    try {
      await widget.onSignOut();
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          failureLine(error, '로그아웃하지 못했어요. 잠시 후 다시 시도해 주세요.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _signOutPending = false);
      }
    }
  }

  /// Asks before the account is given up, as the sign-out does. 삭제 goes
  /// on to the request; where it cannot be made yet the button is off.
  Future<void> _showAccountDeletion() async {
    final canRequest = widget.onRequestAccountDeletion != null;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialogBody(
        title: '계정 삭제',
        body:
            '7일 이내에 로그인하면 삭제가 취소되고 계정이 복구돼요.\n\n'
            '삭제 후에는 데이터를 복구할 수 없어요.',
        actions: <Widget>[
          AppButton(
            label: '취소',
            variant: AppButtonVariant.neutral,
            size: AppButtonSize.popup,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            key: const ValueKey<String>('policy-account-deletion-request'),
            label: canRequest ? '삭제' : '잠시 후 이용 가능',
            size: AppButtonSize.popup,
            isDisabled: !canRequest,
            onPressed: canRequest
                ? () => Navigator.of(context).pop(true)
                : null,
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _submitDeletion();
  }

  Future<void> _submitDeletion() async {
    if (_deletionPending) return;
    setState(() => _deletionPending = true);
    try {
      await widget.onRequestAccountDeletion!();
    } catch (error, stack) {
      if (error is! AccountDeletionException) {
        reportError(error, stack, where: 'withdrawal');
      }
      if (mounted) {
        showAppSnackBar(
          context,
          error is AccountDeletionException
              ? error.message
              : failureLine(error, '계정 삭제 요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.'),
        );
      }
    } finally {
      if (mounted) setState(() => _deletionPending = false);
    }
  }
}

const _panelPadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.md,
  vertical: AppSpacing.xs,
);

class _PolicyDocumentRow extends StatelessWidget {
  const _PolicyDocumentRow({
    required this.title,
    required this.onPressed,
    this.showDivider = false,
  });

  final String title;
  final VoidCallback onPressed;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => AppListRow(
    title: title,
    onPressed: onPressed,
    density: AppListRowDensity.compact,
    inset: AppListRowInset.none,
    showDivider: showDivider,
  );
}
