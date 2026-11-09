abstract final class AccountPolicyVersions {
  static const terms = 'soolgyul-terms-v1';
  static const privacy = 'soolgyul-privacy-v1';
  static const marketing = 'soolgyul-marketing-v1';
}

enum ProfileGender { male, female, other }

class AccountCompletionDraft {
  const AccountCompletionDraft({
    this.birthYear,
    this.birthMonth,
    this.birthDay,
    this.gender,
    this.adultAgeConfirmed = false,
    this.termsAccepted = false,
    this.privacyAccepted = false,
    this.marketingOptIn = false,
  });

  static const oldestBirthYear = 1900;

  final int? birthYear;
  final int? birthMonth;
  final int? birthDay;

  DateTime? get birthDate {
    final year = birthYear;
    final month = birthMonth;
    final day = birthDay;
    if (year == null || month == null || day == null) return null;
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  final ProfileGender? gender;
  final bool adultAgeConfirmed;
  final bool termsAccepted;
  final bool privacyAccepted;
  final bool marketingOptIn;

  static int latestEligibleBirthYear([DateTime? now]) =>
      (now ?? DateTime.now()).year - 19;

  bool get hasEligibleBirthYear {
    final value = birthYear;
    return value != null &&
        value >= oldestBirthYear &&
        value <= latestEligibleBirthYear();
  }

  bool get hasRequiredAgreements =>
      adultAgeConfirmed && termsAccepted && privacyAccepted;

  /// The privacy agreement covers collecting the gender as well.
  bool get genderConsentAccepted => privacyAccepted && gender != null;

  bool get hasGender => gender != null;

  bool get canComplete =>
      hasEligibleBirthYear &&
      birthDate != null &&
      hasGender &&
      hasRequiredAgreements;

  AccountCompletionDraft copyWith({
    int? birthYear,
    int? birthMonth,
    int? birthDay,
    bool clearBirthDay = false,
    ProfileGender? gender,
    bool clearGender = false,
    bool? adultAgeConfirmed,
    bool? termsAccepted,
    bool? privacyAccepted,
    bool? marketingOptIn,
  }) {
    return AccountCompletionDraft(
      birthYear: birthYear ?? this.birthYear,
      birthMonth: birthMonth ?? this.birthMonth,
      birthDay: clearBirthDay ? null : (birthDay ?? this.birthDay),
      gender: clearGender ? null : (gender ?? this.gender),
      adultAgeConfirmed: adultAgeConfirmed ?? this.adultAgeConfirmed,
      termsAccepted: termsAccepted ?? this.termsAccepted,
      privacyAccepted: privacyAccepted ?? this.privacyAccepted,
      marketingOptIn: marketingOptIn ?? this.marketingOptIn,
    );
  }

  AccountCompletionDraft withAllAgreements(bool accepted) {
    return copyWith(
      adultAgeConfirmed: accepted,
      termsAccepted: accepted,
      privacyAccepted: accepted,
      marketingOptIn: accepted,
    );
  }
}
