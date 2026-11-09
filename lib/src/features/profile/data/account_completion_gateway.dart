import 'dart:math';

import 'account_completion_draft.dart';

enum AccountCompletionOperation { fetchStatus, complete }

class AccountCompletionException implements Exception {
  const AccountCompletionException(this.operation, {this.code});

  final AccountCompletionOperation operation;
  final String? code;
}

class CompleteAccountRequest {
  const CompleteAccountRequest({
    required this.idempotencyKey,
    required this.displayName,
    required this.birthYear,
    required this.birthDate,
    required this.adultAgeConfirmed,
    required this.termsAccepted,
    required this.privacyAccepted,
    required this.marketingOptIn,
    this.gender,
    this.genderConsentAccepted = false,
  });

  factory CompleteAccountRequest.fromDraft({
    required String idempotencyKey,
    required String displayName,
    required AccountCompletionDraft draft,
  }) {
    final birthYear = draft.birthYear;
    if (birthYear == null || !draft.canComplete) {
      throw const AccountCompletionException(
        AccountCompletionOperation.complete,
        code: 'account_completion_invalid',
      );
    }
    return CompleteAccountRequest(
      idempotencyKey: idempotencyKey,
      displayName: displayName,
      birthYear: birthYear,
      birthDate: draft.birthDate!,
      adultAgeConfirmed: draft.adultAgeConfirmed,
      termsAccepted: draft.termsAccepted,
      privacyAccepted: draft.privacyAccepted,
      marketingOptIn: draft.marketingOptIn,
      gender: draft.genderConsentAccepted ? draft.gender : null,
      genderConsentAccepted:
          draft.genderConsentAccepted && draft.gender != null,
    );
  }

  final String idempotencyKey;
  final String displayName;
  final int birthYear;
  final DateTime birthDate;
  final ProfileGender? gender;
  final bool genderConsentAccepted;
  final bool adultAgeConfirmed;
  final bool termsAccepted;
  final bool privacyAccepted;
  final bool marketingOptIn;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'idempotency_key': idempotencyKey,
    'display_name': displayName,
    'birth_year': birthYear,
    'birth_date':
        '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
    'gender': genderConsentAccepted ? gender?.name : null,
    'gender_consent_accepted': genderConsentAccepted && gender != null,
    'age_19_or_over_confirmed': adultAgeConfirmed,
    'terms_version': AccountPolicyVersions.terms,
    'privacy_version': AccountPolicyVersions.privacy,
    'marketing_version': AccountPolicyVersions.marketing,
    'terms_accepted': termsAccepted,
    'privacy_accepted': privacyAccepted,
    'marketing_opt_in': marketingOptIn,
  };
}

class AccountCompletionStatus {
  const AccountCompletionStatus({
    required this.profileComplete,
    required this.displayName,
    required this.adultAgeConfirmed,
    required this.termsVersion,
    required this.privacyVersion,
    required this.marketingOptIn,
    required this.deletionState,
  });

  final bool profileComplete;
  final String? displayName;
  final bool adultAgeConfirmed;
  final String? termsVersion;
  final String? privacyVersion;
  final bool marketingOptIn;
  final String deletionState;

  bool get isReady => profileComplete && deletionState == 'active';
}

abstract interface class AccountCompletionGateway {
  Future<AccountCompletionStatus> fetchStatus();

  Future<AccountCompletionStatus> complete(CompleteAccountRequest request);
}

String createAccountCompletionUuidV4([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
