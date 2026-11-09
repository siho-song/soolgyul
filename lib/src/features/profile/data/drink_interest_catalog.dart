import '../../../widgets/app_icon.dart';
import 'profile_setup_draft.dart';

class DrinkInterestOption {
  const DrinkInterestOption({
    required this.value,
    required this.icon,
    required this.emoji,
    this.assetPath,
  });

  final DrinkInterest value;
  final AppIconAsset icon;
  final String emoji;
  final String? assetPath;

  String get wireKey => value.wireKey;
  String get label => value.label;
}

const drinkInterestOptions = <DrinkInterestOption>[
  DrinkInterestOption(
    value: DrinkInterest.wine,
    icon: AppIconAsset.wine,
    emoji: '🍷',
    assetPath: 'assets/component_assets/drink_interests/wine.png',
  ),
  DrinkInterestOption(
    value: DrinkInterest.whisky,
    icon: AppIconAsset.whisky,
    emoji: '🥃',
    assetPath: 'assets/component_assets/drink_interests/whisky.png',
  ),
  DrinkInterestOption(
    value: DrinkInterest.koreanTraditional,
    icon: AppIconAsset.traditional,
    emoji: '🏺',
    assetPath: 'assets/component_assets/drink_interests/traditional.png',
  ),
  DrinkInterestOption(
    value: DrinkInterest.sake,
    icon: AppIconAsset.sake,
    emoji: '🍶',
    assetPath: 'assets/component_assets/drink_interests/sake.png',
  ),
];

const initialProfileDrinkInterests = <DrinkInterest>{
  DrinkInterest.wine,
  DrinkInterest.whisky,
  DrinkInterest.koreanTraditional,
  DrinkInterest.sake,
};
