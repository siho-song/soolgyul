import 'package:flutter/material.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_list_row.dart';
import '../../../widgets/app_sheet.dart';
import '../../../widgets/app_surface.dart';
import '../data/marketing_consent_gateway.dart';
import '../data/account_deletion_gateway.dart';
import 'widgets/marketing_consent_control.dart';
import 'legal_document_link.dart';
import '../../../widgets/app_snack_bar.dart';

class PolicyScreen extends StatefulWidget {
  const PolicyScreen({
    required this.onSignOut,
    this.onRequestAccountDeletion,
    this.marketingConsentGateway,
    this.isActive = true,
    super.key,
  });

  final Future<void> Function() onSignOut;
  final Future<void> Function()? onRequestAccountDeletion;
  final MarketingConsentGateway? marketingConsentGateway;
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
          child: SizedBox(
            height: AppSizes.menuRowHeight,
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '마케팅 정보 수신 동의',
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
                density: AppListRowDensity.compact,
                inset: AppListRowInset.none,
                showDivider: true,
              ),
              AppListRow(
                key: const ValueKey<String>('policy-account-deletion'),
                title: '회원 탈퇴',
                onPressed: _deletionPending || _signOutPending
                    ? null
                    : _showAccountDeletion,
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

  Future<void> _confirmSignOut() async {
    final confirmed = await showAppSheet<bool>(
      context: context,
      builder: (context) => AppSheetBody(
        title: '로그아웃하시겠어요?',
        body: '로그인 상태가 해제돼요. 다시 로그인하면 언제든 기록을 이어볼 수 있어요.',
        children: <Widget>[
          AppButton(
            key: const ValueKey<String>('policy-sign-out-confirm'),
            label: '로그아웃',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: '취소',
            variant: AppButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop(false),
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
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, '로그아웃하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) {
        setState(() => _signOutPending = false);
      }
    }
  }

  Future<void> _showAccountDeletion() => showAppSheet<void>(
    context: context,
    builder: (context) => AppSheetBody(
      title: '정말 탈퇴하시겠어요?',
      body:
          '탈퇴를 요청하시면 바로 서비스 이용이 중단돼요.\n'
          '지금까지 기록한 술결 카드와 메모, 관심 목록이 모두 사라져요.\n\n'
          '30일 이내에 다시 로그인하면 탈퇴가 취소되고 계정이 복구돼요.\n'
          '30일 후에는 데이터가 완전히 파기되며 새로운 가입이 가능해요.',
      children: <Widget>[
        // Staying is the main action; the withdrawal sits below it.
        AppButton(label: '취소', onPressed: () => Navigator.of(context).pop()),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const ValueKey<String>('policy-account-deletion-request'),
          label: widget.onRequestAccountDeletion == null
              ? '잠시 후 이용 가능'
              : '탈퇴하기',
          variant: AppButtonVariant.tertiary,
          isDisabled: widget.onRequestAccountDeletion == null,
          onPressed: widget.onRequestAccountDeletion == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  _submitDeletion();
                },
        ),
      ],
    ),
  );

  Future<void> _submitDeletion() async {
    if (_deletionPending) return;
    setState(() => _deletionPending = true);
    try {
      await widget.onRequestAccountDeletion!();
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          error is AccountDeletionException
              ? error.message
              : '탈퇴 요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.',
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

/// Confirmation sheet: title, explanation and its points, then the action
/// buttons.
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
