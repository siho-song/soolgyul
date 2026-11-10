import 'package:characters/characters.dart';

enum DrinkInterest { wine, whisky, koreanTraditional, sake }

extension DrinkInterestMetadata on DrinkInterest {
  String get wireKey => switch (this) {
    DrinkInterest.wine => 'wine',
    DrinkInterest.whisky => 'whisky',
    DrinkInterest.koreanTraditional => 'korean_traditional',
    DrinkInterest.sake => 'sake',
  };

  String get label => switch (this) {
    DrinkInterest.wine => '와인',
    DrinkInterest.whisky => '위스키',
    DrinkInterest.koreanTraditional => '전통주',
    DrinkInterest.sake => '사케',
  };
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
