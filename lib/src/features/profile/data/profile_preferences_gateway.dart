import '../../../core/catalog/drink_type.dart';
import 'account_completion_draft.dart';

class ProfilePreferences {
  ProfilePreferences({
    required this.displayName,
    required Iterable<DrinkType> interests,
    this.gender,
  }) : interests = Set<DrinkType>.unmodifiable(interests);

  final String? displayName;
  final Set<DrinkType> interests;

  /// The gender given at sign-up; `null` when none is stored.
  final ProfileGender? gender;
}

abstract interface class ProfilePreferencesGateway {
  Future<ProfilePreferences> fetchProfilePreferences();

  Future<String> updateDisplayName(String displayName);

  Future<Set<DrinkType>> replaceDrinkInterests(Set<DrinkType> interests);
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
