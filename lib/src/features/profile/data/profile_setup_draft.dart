import 'package:characters/characters.dart';

import '../../../core/catalog/drink_type.dart';

class ProfileSetupDraft {
  ProfileSetupDraft({
    required String displayName,
    Iterable<DrinkType> interestedDrinkTypes = const <DrinkType>[],
  }) : displayName = displayName.trim(),
       interestedDrinkTypes = Set<DrinkType>.unmodifiable(interestedDrinkTypes);

  static const int maximumDisplayNameLength = 12;
  static const int minimumDisplayNameLength = 2;
  static final RegExp _displayNamePattern = RegExp(r'^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]+$');

  final String displayName;
  final Set<DrinkType> interestedDrinkTypes;

  bool get hasValidDisplayName {
    final length = displayName.characters.length;
    return length >= minimumDisplayNameLength &&
        length <= maximumDisplayNameLength &&
        _displayNamePattern.hasMatch(displayName);
  }

  bool get hasValidDrinkInterests => interestedDrinkTypes.isNotEmpty;

  ProfileSetupDraft copyWith({
    String? displayName,
    Iterable<DrinkType>? interestedDrinkTypes,
  }) {
    return ProfileSetupDraft(
      displayName: displayName ?? this.displayName,
      interestedDrinkTypes: interestedDrinkTypes ?? this.interestedDrinkTypes,
    );
  }

  ProfileSetupDraft toggleDrinkInterest(DrinkType drinkInterest) {
    final updatedDrinkTypes = Set<DrinkType>.of(interestedDrinkTypes);
    if (updatedDrinkTypes.contains(drinkInterest)) {
      updatedDrinkTypes.remove(drinkInterest);
    } else {
      updatedDrinkTypes.add(drinkInterest);
    }
    return copyWith(interestedDrinkTypes: updatedDrinkTypes);
  }
}
