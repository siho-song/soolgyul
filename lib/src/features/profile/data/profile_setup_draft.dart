import 'package:characters/characters.dart';

import '../../../core/catalog/drink_type.dart';

/// A 주종 a member can be interested in, in the order the pickers show them.
enum DrinkInterest {
  wine(DrinkType.wine),
  whisky(DrinkType.whisky),
  koreanTraditional(DrinkType.koreanTraditional),
  sake(DrinkType.sake);

  const DrinkInterest(this.type);
  final DrinkType type;

  String get wireKey => type.key;
  String get label => type.label;
}

class ProfileSetupDraft {
  ProfileSetupDraft({
    required String displayName,
    Iterable<DrinkInterest> interestedDrinkTypes = const <DrinkInterest>[],
  }) : displayName = displayName.trim(),
       interestedDrinkTypes = Set<DrinkInterest>.unmodifiable(
         interestedDrinkTypes,
       );

  static const int maximumDisplayNameLength = 12;
  static const int minimumDisplayNameLength = 2;
  static final RegExp _displayNamePattern = RegExp(r'^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ]+$');

  final String displayName;
  final Set<DrinkInterest> interestedDrinkTypes;

  bool get hasValidDisplayName {
    final length = displayName.characters.length;
    return length >= minimumDisplayNameLength &&
        length <= maximumDisplayNameLength &&
        _displayNamePattern.hasMatch(displayName);
  }

  bool get hasValidDrinkInterests => interestedDrinkTypes.isNotEmpty;

  ProfileSetupDraft copyWith({
    String? displayName,
    Iterable<DrinkInterest>? interestedDrinkTypes,
  }) {
    return ProfileSetupDraft(
      displayName: displayName ?? this.displayName,
      interestedDrinkTypes: interestedDrinkTypes ?? this.interestedDrinkTypes,
    );
  }

  ProfileSetupDraft toggleDrinkInterest(DrinkInterest drinkInterest) {
    final updatedDrinkTypes = Set<DrinkInterest>.of(interestedDrinkTypes);
    if (updatedDrinkTypes.contains(drinkInterest)) {
      updatedDrinkTypes.remove(drinkInterest);
    } else {
      updatedDrinkTypes.add(drinkInterest);
    }
    return copyWith(interestedDrinkTypes: updatedDrinkTypes);
  }
}
