import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_search_gateway.dart';

/// Small deterministic fixture set for building the adaptive questionnaire.
///
/// These are intentionally not production catalog records.
abstract final class TestCatalog {
  static const CatalogDrink dryWhiteWine = CatalogDrink(
    id: 'fixture-dry-white-wine',
    displayName: '테스트 드라이 화이트 와인',
    category: DrinkCategory.whiteWine,
    styleLabel: '드라이 화이트 와인',
    abvPercent: 12.5,
    traitEvidence: <DrinkTrait, DrinkTraitEvidence>{
      DrinkTrait.carbonation: DrinkTraitEvidence.verifiedAbsent,
      DrinkTrait.acidity: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.fruitAroma: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.lightBody: DrinkTraitEvidence.verifiedPresent,
    },
  );

  static const CatalogDrink sparklingWine = CatalogDrink(
    id: 'fixture-brut-sparkling-wine',
    displayName: '테스트 브뤼 스파클링 와인',
    category: DrinkCategory.sparklingWine,
    styleLabel: '브뤼 스파클링 와인',
    abvPercent: 11.5,
    traitEvidence: <DrinkTrait, DrinkTraitEvidence>{
      DrinkTrait.carbonation: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.acidity: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.fruitAroma: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.lightBody: DrinkTraitEvidence.verifiedPresent,
    },
  );

  static const CatalogDrink smokyWhisky = CatalogDrink(
    id: 'fixture-smoky-whisky',
    displayName: '테스트 스모키 위스키',
    category: DrinkCategory.whisky,
    styleLabel: '피티드 싱글 몰트',
    abvPercent: 46,
    traitEvidence: <DrinkTrait, DrinkTraitEvidence>{
      DrinkTrait.carbonation: DrinkTraitEvidence.verifiedAbsent,
      DrinkTrait.smokeRoast: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.oakVanilla: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.alcoholPresence: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.warming: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.overallIntensity: DrinkTraitEvidence.verifiedPresent,
    },
  );

  static const CatalogDrink mellowWhisky = CatalogDrink(
    id: 'fixture-mellow-whisky',
    displayName: '테스트 부드러운 위스키',
    category: DrinkCategory.whisky,
    styleLabel: '언피티드 몰트 위스키',
    abvPercent: 40,
    traitEvidence: <DrinkTrait, DrinkTraitEvidence>{
      DrinkTrait.carbonation: DrinkTraitEvidence.verifiedAbsent,
      DrinkTrait.oakVanilla: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.fruitAroma: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.smoothTexture: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.alcoholPresence: DrinkTraitEvidence.verifiedPresent,
    },
  );

  static const CatalogDrink junmaiSake = CatalogDrink(
    id: 'fixture-junmai-sake',
    displayName: '테스트 준마이 사케',
    category: DrinkCategory.sake,
    styleLabel: '준마이',
    abvPercent: 15,
    traitEvidence: <DrinkTrait, DrinkTraitEvidence>{
      DrinkTrait.carbonation: DrinkTraitEvidence.verifiedAbsent,
      DrinkTrait.grainAroma: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.smoothTexture: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.alcoholPresence: DrinkTraitEvidence.verifiedPresent,
    },
  );

  static const CatalogDrink makgeolli = CatalogDrink(
    id: 'fixture-makgeolli',
    displayName: '테스트 생막걸리',
    category: DrinkCategory.koreanTraditional,
    styleLabel: '생막걸리',
    abvPercent: 6,
    traitEvidence: <DrinkTrait, DrinkTraitEvidence>{
      DrinkTrait.carbonation: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.acidity: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.grainAroma: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.smoothTexture: DrinkTraitEvidence.verifiedPresent,
    },
  );

  static const CatalogDrink tannicRedWine = CatalogDrink(
    id: 'fixture-tannic-red-wine',
    displayName: '테스트 탄닌 레드 와인',
    category: DrinkCategory.redWine,
    styleLabel: '풀바디 레드 와인',
    abvPercent: 13.5,
    traitEvidence: <DrinkTrait, DrinkTraitEvidence>{
      DrinkTrait.carbonation: DrinkTraitEvidence.verifiedAbsent,
      DrinkTrait.fruitAroma: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.astringency: DrinkTraitEvidence.verifiedPresent,
      DrinkTrait.fullBody: DrinkTraitEvidence.verifiedPresent,
    },
  );

  static const List<CatalogDrink> drinks = <CatalogDrink>[
    dryWhiteWine,
    sparklingWine,
    smokyWhisky,
    mellowWhisky,
    junmaiSake,
    makgeolli,
    tannicRedWine,
  ];
}

/// Searches [TestCatalog.drinks] by name, as the server would.
class TestCatalogGateway implements CatalogSearchGateway {
  const TestCatalogGateway();

  @override
  Future<List<CatalogDrink>> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final wanted = query.replaceAll(' ', '');
    return TestCatalog.drinks
        .where(
          (drink) => drink.displayName.replaceAll(' ', '').contains(wanted),
        )
        .skip(offset)
        .take(limit)
        .toList();
  }
}

/// Waits out the pause the search keeps after typing, then its answer.
Future<void> pumpCatalogSearch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}
