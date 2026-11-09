import '../../../core/drink_entry_method.dart';
import '../../catalog/data/catalog_drink.dart';

class OnboardingEntryDraft {
  const OnboardingEntryDraft._({
    required this.entryMethod,
    this.drinkName,
    this.drinkSelection,
  });

  factory OnboardingEntryDraft.fromDrinkSelection(
    DrinkSelection drinkSelection,
  ) {
    final normalizedName = drinkSelection.displayName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        drinkSelection.displayName,
        'drinkSelection',
        '술 이름은 필수입니다.',
      );
    }
    return OnboardingEntryDraft._(
      entryMethod: DrinkEntryMethod.drinkName,
      drinkName: normalizedName,
      drinkSelection: drinkSelection,
    );
  }

  const OnboardingEntryDraft.fromFeelingOnly()
    : this._(entryMethod: DrinkEntryMethod.feelingOnly);

  final DrinkEntryMethod entryMethod;
  final String? drinkName;
  final DrinkSelection? drinkSelection;

  bool get canContinue {
    return switch (entryMethod) {
      DrinkEntryMethod.drinkName =>
        (drinkName?.isNotEmpty ?? false) && drinkSelection != null,
      DrinkEntryMethod.feelingOnly => false,
      DrinkEntryMethod.photo => false,
    };
  }
}
