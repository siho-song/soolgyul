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
        'account_restore_unavailable' => '계정 복구 가능 기간이 만료되었어요.',
        'provider_configuration_missing' =>
          '소셜 계정 연동 해제에 실패했어요. 고객센터로 문의해 주세요.',
        'provider_identity_mismatch' => '현재 로그인된 소셜 계정과 일치하지 않아요.',
        'linked_provider_review_required' =>
          '복수의 소셜 계정이 연결되어 있어 자동 탈퇴가 어려워요. 1:1 문의를 이용해 주세요.',
        'provider_reauthentication_required' ||
        'provider_verification_failed' => '본인 확인을 위해 소셜 로그인을 다시 진행해 주세요.',
        _ => '탈퇴 처리를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
      });
    }
  }

  /// Read straight from the database: asking only needs the caller's own
  /// session, so it skips the server function the changes go through.
  @override
  Future<AccountDeletionStatus> fetchStatus() async {
    try {
      final state = await client.rpc('soolgyul_get_my_deletion_state');
      return AccountDeletionStatus.fromJson(
        Map<String, dynamic>.from(state as Map),
      );
    } on PostgrestException {
      throw const AccountDeletionException('계정 상태를 확인하지 못했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Future<void> requestDeletion() async {
    final previous = await fetchStatus();
    if (previous.state == 'purged') {
      throw const AccountDeletionException('이미 삭제가 완료된 계정이에요.');
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
