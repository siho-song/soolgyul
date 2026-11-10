import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_completion_gateway.dart';

class SupabaseAccountCompletionGateway implements AccountCompletionGateway {
  SupabaseAccountCompletionGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<AccountCompletionStatus> fetchStatus() async {
    // Read straight from the database: asking only needs the caller's own
    // session, so it skips the server function the completion goes through.
    try {
      return _parseStatus(await _client.rpc('soolgyul_get_my_profile_status'));
    } on AccountCompletionException {
      rethrow;
    } catch (_) {
      throw const AccountCompletionException(
        AccountCompletionOperation.fetchStatus,
      );
    }
  }

  @override
  Future<AccountCompletionStatus> complete(
    CompleteAccountRequest request,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'complete-profile',
        body: request.toJson(),
      );
      final status = _parseStatus(response.data);
      if (!status.isReady ||
          status.displayName == null ||
          !status.adultAgeConfirmed ||
          status.termsVersion == null ||
          status.privacyVersion == null) {
        throw const AccountCompletionException(
          AccountCompletionOperation.complete,
          code: 'invalid_response',
        );
      }
      return status;
    } on AccountCompletionException {
      rethrow;
    } on FunctionException catch (error) {
      throw AccountCompletionException(
        AccountCompletionOperation.complete,
        code: _publicErrorCode(error.details),
      );
    } catch (_) {
      throw const AccountCompletionException(
        AccountCompletionOperation.complete,
      );
    }
  }

  static AccountCompletionStatus _parseStatus(dynamic value) {
    if (value is! Map) {
      throw const AccountCompletionException(
        AccountCompletionOperation.complete,
        code: 'invalid_response',
      );
    }
    final row = Map<String, dynamic>.from(value);
    if (row['profile_complete'] is! bool ||
        (row['display_name'] != null && row['display_name'] is! String) ||
        row['age_19_or_over_confirmed'] is! bool ||
        (row['terms_version'] != null && row['terms_version'] is! String) ||
        (row['privacy_version'] != null && row['privacy_version'] is! String) ||
        row['marketing_opt_in'] is! bool ||
        (row['deletion_state'] != 'active' &&
            row['deletion_state'] != 'scheduled')) {
      throw const AccountCompletionException(
        AccountCompletionOperation.complete,
        code: 'invalid_response',
      );
    }
    return AccountCompletionStatus(
      profileComplete: row['profile_complete'] as bool,
      displayName: row['display_name'] as String?,
      adultAgeConfirmed: row['age_19_or_over_confirmed'] as bool,
      termsVersion: row['terms_version'] as String?,
      privacyVersion: row['privacy_version'] as String?,
      marketingOptIn: row['marketing_opt_in'] as bool,
      deletionState: row['deletion_state'] as String,
    );
  }
}

String? _publicErrorCode(Object? details) {
  if (details is Map && details['error_code'] is String) {
    return details['error_code'] as String;
  }
  return null;
}
