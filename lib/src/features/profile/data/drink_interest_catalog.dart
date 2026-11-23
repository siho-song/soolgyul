import '../../../widgets/app_icon.dart';
import '../../../core/catalog/drink_type.dart';

/// A 주종 as the interest pickers draw it: its icon and its picture.
class DrinkInterestOption {
  const DrinkInterestOption({
    required this.value,
    required this.icon,
    required this.emoji,
    this.assetPath,
  });

  final DrinkType value;
  final AppIconAsset icon;
  final String emoji;
  final String? assetPath;

  String get wireKey => value.key;
  String get label => value.label;
}

DrinkInterestOption _optionOf(DrinkType type) => switch (type) {
  DrinkType.wine => const DrinkInterestOption(
    value: DrinkType.wine,
    icon: AppIconAsset.wine,
    emoji: '🍷',
    assetPath: 'assets/images/drink_interests/wine.png',
  ),
  DrinkType.whisky => const DrinkInterestOption(
    value: DrinkType.whisky,
    icon: AppIconAsset.whisky,
    emoji: '🥃',
    assetPath: 'assets/images/drink_interests/whisky.png',
  ),
  DrinkType.sake => const DrinkInterestOption(
    value: DrinkType.sake,
    icon: AppIconAsset.sake,
    emoji: '🍶',
    assetPath: 'assets/images/drink_interests/sake.png',
  ),
  DrinkType.koreanTraditional => const DrinkInterestOption(
    value: DrinkType.koreanTraditional,
    icon: AppIconAsset.traditional,
    emoji: '🏺',
    assetPath: 'assets/images/drink_interests/traditional.png',
  ),
};

/// Every 주종 a member can be interested in, in the one order the app lists
/// them (core/catalog/drink_type.dart).
final drinkInterestOptions = <DrinkInterestOption>[
  for (final type in DrinkType.values) _optionOf(type),
];
