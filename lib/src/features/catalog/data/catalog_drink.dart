import '../../../core/catalog/drink_type.dart';
import '../../../core/format/abv.dart';

enum DrinkCategory {
  redWine(DrinkType.wine),
  whiteWine(DrinkType.wine),
  sparklingWine(DrinkType.wine),
  whisky(DrinkType.whisky),
  sake(DrinkType.sake),
  koreanTraditional(DrinkType.koreanTraditional),
  other(null);

  const DrinkCategory(this.type);

  /// Its 주종; null for a drink of none the app records.
  final DrinkType? type;
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

/// What the catalog knows of a bottle that its label can show. The label
/// search answers it with each drink, so a label's candidates are weighed
/// by more than their names.
class DrinkLabelFacts {
  const DrinkLabelFacts({
    this.vintageYear,
    this.ageYears,
    this.grapes = const <String>[],
    this.names = const <String>[],
    this.regions = const <List<String>>[],
    this.producer = const <String>[],
    this.known = false,
    this.staple = false,
  });

  final int? vintageYear;
  final double? ageYears;

  /// Grape keys ('cabernet_sauvignon').
  final List<String> grapes;

  /// The names the bottle goes by besides its catalog names, as its label
  /// prints them in its own script ('真澄 銀撰').
  final List<String> names;

  /// The bottle's place first, then each place it lies in; a place is the
  /// names it goes by ('콜차구아 밸리', 'Colchagua Valley').
  final List<List<String>> regions;

  /// The names the producer goes by.
  final List<String> producer;

  /// A bottle picked by hand as one people know, and the producer's
  /// everyday bottle among those.
  final bool known;
  final bool staple;

  /// The facts as the label search answers them; `null` for anything that
  /// is not that answer.
  static DrinkLabelFacts? fromJson(Object? value) {
    if (value is! Map) return null;
    List<String> names(Object? list) => <String>[
      if (list is List)
        for (final name in list)
          if (name is String && name.trim().isNotEmpty) name.trim(),
    ];
    final vintage = value['vintage'];
    final age = value['age'];
    final regions = value['regions'];
    return DrinkLabelFacts(
      vintageYear: vintage is num ? vintage.toInt() : null,
      ageYears: age is num ? age.toDouble() : null,
      grapes: names(value['grapes']),
      names: names(value['names']),
      regions: <List<String>>[
        if (regions is List)
          for (final place in regions)
            if (names(place).isNotEmpty) names(place),
      ],
      producer: names(value['producer']),
      known: value['known'] == true,
      staple: value['staple'] == true,
    );
  }
}

class CatalogDrink {
  const CatalogDrink({
    required this.id,
    required this.displayName,
    required this.category,
    this.categoryKey,
    this.styleKey,
    this.styleLabel,
    this.abvPercent,
    this.traitEvidence = const <DrinkTrait, DrinkTraitEvidence>{},
    this.nameEn,
    this.photoUrl,
    this.countryCode,
    this.region,
    this.labelFacts,
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

  /// The catalog's keys for the drink's 주종 and its kind within it
  /// (`wine`, `rose_wine`), as the server gave them; null on a drink that
  /// came without them. The gauge sheet is read by these.
  final String? categoryKey;
  final String? styleKey;
  final String? styleLabel;
  final double? abvPercent;
  final Map<DrinkTrait, DrinkTraitEvidence> traitEvidence;

  /// Set only on a drink the label search found.
  final DrinkLabelFacts? labelFacts;

  /// '11.5%' or '40%': whole numbers drop the decimal.
  String? get abvLabel {
    final abv = abvPercent;
    return abv == null ? null : formatAbv(abv);
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
