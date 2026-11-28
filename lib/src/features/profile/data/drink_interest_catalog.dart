import '../../../core/catalog/drink_type.dart';

/// A 주종 as the interest pickers draw it: its emoji and its picture.
class DrinkInterestOption {
  const DrinkInterestOption({
    required this.value,
    required this.emoji,
    required this.assetPath,
  });

  final DrinkType value;
  final String emoji;
  final String assetPath;

  String get wireKey => value.key;
  String get label => value.label;
}

DrinkInterestOption _optionOf(DrinkType type) => switch (type) {
  DrinkType.wine => const DrinkInterestOption(
    value: DrinkType.wine,
    emoji: '🍷',
    assetPath: 'assets/images/drink_interests/wine.png',
  ),
  DrinkType.whisky => const DrinkInterestOption(
    value: DrinkType.whisky,
    emoji: '🥃',
    assetPath: 'assets/images/drink_interests/whisky.png',
  ),
  DrinkType.sake => const DrinkInterestOption(
    value: DrinkType.sake,
    emoji: '🍶',
    assetPath: 'assets/images/drink_interests/sake.png',
  ),
  DrinkType.koreanTraditional => const DrinkInterestOption(
    value: DrinkType.koreanTraditional,
    emoji: '🏺',
    assetPath: 'assets/images/drink_interests/traditional.png',
  ),
};

/// Every 주종 a member can be interested in, in the one order the app lists
/// them (core/catalog/drink_type.dart).
final drinkInterestOptions = <DrinkInterestOption>[
  for (final type in DrinkType.values) _optionOf(type),
];
