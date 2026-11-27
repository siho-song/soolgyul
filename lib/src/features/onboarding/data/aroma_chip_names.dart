import 'package:flutter/foundation.dart';

import '../adaptive/onboarding_aroma_menu.dart';

/// The aroma question's chip by the dictionary's name of its aroma (체리 →
/// the cherry chip), for a sheet that is given an aroma by its name alone and
/// draws its picture. The menus hold keys and the names are the
/// dictionary's, so this is empty until the dictionary's words are read
/// ([nameAromaChips]).
final aromaChipByName = ValueNotifier<Map<String, OnboardingAromaChip>>(
  const {},
);

/// Names every menu chip by [nameOf], the dictionary's word for an aroma's
/// key.
void nameAromaChips(String? Function(String key) nameOf) {
  aromaChipByName.value = {
    for (final chip in OnboardingAromaMenu.chips) ?nameOf(chip.key): chip,
  };
}
