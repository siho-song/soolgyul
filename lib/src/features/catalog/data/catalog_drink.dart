enum DrinkCategory {
  redWine,
  whiteWine,
  sparklingWine,
  whisky,
  sake,
  koreanTraditional,
  other,
}

/// Product facts that can influence option order without deciding what the
/// user actually experienced.
enum DrinkTrait {
  carbonation,
  sweetness,
  acidity,
  bitterness,
  astringency,
  fruitAroma,
  floralAroma,
  grainAroma,
  oakVanilla,
  smokeRoast,
  herbalAroma,
  alcoholPresence,
  warming,
  smoothTexture,
  lightBody,
  fullBody,
  overallIntensity,
}

/// `verifiedAbsent` is intentionally stronger than missing data. It should be
/// used only when a trait is known not to apply, rather than when it simply has
/// not been collected yet.
enum DrinkTraitEvidence { verifiedPresent, verifiedAbsent, unknown }

class CatalogDrink {
  const CatalogDrink({
    required this.id,
    required this.displayName,
    required this.category,
    this.styleLabel,
    this.abvPercent,
    this.traitEvidence = const <DrinkTrait, DrinkTraitEvidence>{},
    this.nameEn,
    this.photoUrl,
    this.countryCode,
    this.region,
  });

  final String id;
  final String displayName;
  final String? nameEn;
  final String? photoUrl;

  /// ISO 3166-1 alpha-2 code of the producing country.
  final String? countryCode;

  /// Korean name of the product's region row ('꼬뜨 드 뉘'), as the search returns it.
  final String? region;
  final DrinkCategory category;
  final String? styleLabel;
  final double? abvPercent;
  final Map<DrinkTrait, DrinkTraitEvidence> traitEvidence;

  /// '11.5%' or '40%': whole numbers drop the decimal.
  String? get abvLabel {
    final abv = abvPercent;
    return abv == null ? null : '${abv % 1 == 0 ? abv.toInt() : abv}%';
  }

  DrinkTraitEvidence evidenceFor(DrinkTrait trait) {
    return traitEvidence[trait] ?? DrinkTraitEvidence.unknown;
  }
}

/// The catalog item the reader picked; every record points at one, whether
/// it came from the production catalog or a local test fixture.
class DrinkSelection {
  const DrinkSelection.catalogMatch(this.catalogDrink);

  final CatalogDrink catalogDrink;

  String get displayName => catalogDrink.displayName;

  String get catalogId => catalogDrink.id;

  DrinkCategory get category => catalogDrink.category;

  DrinkTraitEvidence evidenceFor(DrinkTrait trait) =>
      catalogDrink.evidenceFor(trait);
}
