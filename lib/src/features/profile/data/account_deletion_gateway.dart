import 'package:supabase_flutter/supabase_flutter.dart';

class AccountDeletionStatus {
  const AccountDeletionStatus({
    required this.state,
    this.deadline,
    this.canRestore = false,
    this.providerRevoked = false,
  });
  final String state;
  final DateTime? deadline;
  final bool canRestore;
  final bool providerRevoked;
  factory AccountDeletionStatus.fromJson(Map<String, dynamic> json) =>
      AccountDeletionStatus(
        state: json['deletion_state'] as String,
        deadline: DateTime.tryParse(
          json['scheduled_deletion_at'] as String? ?? '',
        ),
        canRestore: json['restore_available'] == true,
        providerRevoked: json['provider_revoked'] == true,
      );
}

abstract interface class AccountDeletionGateway {
  Future<AccountDeletionStatus> fetchStatus();
  Future<void> requestDeletion();
  Future<void> restore();
}

class SupabaseAccountDeletionGateway implements AccountDeletionGateway {
  SupabaseAccountDeletionGateway(
    this.client, {
    required this.loadProviderProof,
  });
  final SupabaseClient client;
  final Future<Map<String, dynamic>> Function() loadProviderProof;

  Future<AccountDeletionStatus> _call({Map<String, dynamic>? body}) async {
    try {
      final result = await client.functions.invoke(
        'account-deletion',
        method: body == null ? HttpMethod.get : HttpMethod.post,
        body: body,
      );
      return AccountDeletionStatus.fromJson(
        Map<String, dynamic>.from(result.data as Map),
      );
    } on FunctionException catch (error) {
      final data = error.details;
      final code = data is Map ? data['error_code'] : null;
      throw AccountDeletionException(switch (code) {
        'restore_window_closed' ||
        'account_restore_unavailable' => '복구 가능한 기간이 지났어요.',
        'provider_configuration_missing' =>
          '소셜 연결 해제 설정이 아직 완료되지 않았어요. 고객 문의로 알려주세요.',
        'provider_identity_mismatch' => '현재 로그인한 계정과 같은 소셜 계정을 선택해주세요.',
        'linked_provider_review_required' =>
          '여러 소셜 계정이 연결되어 있어요. 고객 문의로 탈퇴를 요청해주세요.',
        'provider_reauthentication_required' ||
        'provider_verification_failed' => '소셜 로그인을 다시 진행한 뒤 시도해주세요.',
        _ => '처리를 완료하지 못했어요. 다시 시도해주세요. 탈퇴 상태는 재접속 시 확인할 수 있어요.',
      });
    }
  }

  @override
  Future<AccountDeletionStatus> fetchStatus() => _call();
  @override
  Future<void> requestDeletion() async {
    final previous = await fetchStatus();
    if (previous.state == 'purged') {
      throw const AccountDeletionException('이미 삭제 처리된 계정이에요.');
    }
    final proof = previous.providerRevoked
        ? <String, dynamic>{}
        : await loadProviderProof();
    await _call(body: {'action': 'request', 'confirmed': true, 'proof': proof});
    // The server revokes refresh sessions. Always clear this device's session too.
    await client.auth.signOut(scope: SignOutScope.local);
  }

  @override
  Future<void> restore() async {
    await _call(body: {'action': 'restore'});
  }
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);
  final String message;
  @override
  String toString() => message;
}
