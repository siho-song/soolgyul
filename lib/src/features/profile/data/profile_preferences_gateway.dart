import 'account_completion_draft.dart';
import 'profile_setup_draft.dart';

class ProfilePreferences {
  ProfilePreferences({
    required this.displayName,
    required Iterable<DrinkInterest> interests,
    this.gender,
  }) : interests = Set<DrinkInterest>.unmodifiable(interests);

  final String? displayName;
  final Set<DrinkInterest> interests;

  /// The gender given at sign-up; `null` when none is stored.
  final ProfileGender? gender;
}

abstract interface class ProfilePreferencesGateway {
  Future<ProfilePreferences> fetchProfilePreferences();

  Future<String> updateDisplayName(String displayName);

  Future<Set<DrinkInterest>> replaceDrinkInterests(
    Set<DrinkInterest> interests,
  );
}

enum ProfilePreferencesOperation {
  fetch,
  updateDisplayName,
  replaceDrinkInterests,
}

class ProfilePreferencesException implements Exception {
  const ProfilePreferencesException(this.operation);

  final ProfilePreferencesOperation operation;
}
