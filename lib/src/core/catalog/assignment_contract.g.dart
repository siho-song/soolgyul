// GENERATED. Run python3 -m tools.catalog.enrichment.generate_assignment_contract
// Do not edit: catalog/dictionary/terms.json owns these rules.
// dart format off
enum CatalogCategoryKey {
  koreanTraditional('korean_traditional'),
  sake('sake'),
  whisky('whisky'),
  wine('wine');
  const CatalogCategoryKey(this.key);
  final String key;
  static final _byKey = {for (final v in values) v.key: v};
  static CatalogCategoryKey? fromKey(String key) => _byKey[key];
}

enum CatalogStyleKey {
  americanWhisky('american_whisky'),
  blendedMaltWhisky('blended_malt_whisky'),
  blendedWhisky('blended_whisky'),
  bourbon('bourbon'),
  cornWhisky('corn_whisky'),
  daiginjo('daiginjo'),
  dilutedSoju('diluted_soju'),
  distilledSoju('distilled_soju'),
  fortifiedWine('fortified_wine'),
  futsushu('futsushu'),
  ginjo('ginjo'),
  grainWhisky('grain_whisky'),
  gwahaju('gwahaju'),
  honjozo('honjozo'),
  junmai('junmai'),
  junmaiDaiginjo('junmai_daiginjo'),
  junmaiGinjo('junmai_ginjo'),
  koreanCheongju('korean_cheongju'),
  koreanFruitWine('korean_fruit_wine'),
  madeiraWine('madeira_wine'),
  orangeWine('orange_wine'),
  portWine('port_wine'),
  redWine('red_wine'),
  roseWine('rose_wine'),
  ryeWhisky('rye_whisky'),
  sherryWine('sherry_wine'),
  singleMaltWhisky('single_malt_whisky'),
  singlePotStillWhisky('single_pot_still_whisky'),
  sparklingWine('sparkling_wine'),
  takju('takju'),
  tennesseeWhisky('tennessee_whisky'),
  vermouth('vermouth'),
  wheatWhisky('wheat_whisky'),
  whiteWine('white_wine'),
  yakju('yakju');
  const CatalogStyleKey(this.key);
  final String key;
  static final _byKey = {for (final v in values) v.key: v};
  static CatalogStyleKey? fromKey(String key) => _byKey[key];
}

enum CatalogIngredientKey {
  appleFruit('apple_fruit'),
  apricotFruit('apricot_fruit'),
  aroniaFruit('aronia_fruit'),
  barley('barley'),
  berryFruit('berry_fruit'),
  blueberryFruit('blueberry_fruit'),
  bokbunjaFruit('bokbunja_fruit'),
  buckwheat('buckwheat'),
  caramelColour('caramel_colour'),
  cherryFruit('cherry_fruit'),
  citrusFruit('citrus_fruit'),
  corn('corn'),
  glutinousRice('glutinous_rice'),
  grape('grape'),
  hardyKiwiFruit('hardy_kiwi_fruit'),
  herbBotanical('herb_botanical'),
  honey('honey'),
  hopMaterial('hop_material'),
  kojiStarter('koji_starter'),
  lacticBacteria('lactic_bacteria'),
  maltedBarley('malted_barley'),
  meoruFruit('meoru_fruit'),
  millet('millet'),
  mulberryFruit('mulberry_fruit'),
  nurukStarter('nuruk_starter'),
  oat('oat'),
  omijaFruit('omija_fruit'),
  peachFruit('peach_fruit'),
  pearFruit('pear_fruit'),
  persimmonFruit('persimmon_fruit'),
  plumFruit('plum_fruit'),
  pomegranateFruit('pomegranate_fruit'),
  quinceFruit('quince_fruit'),
  rice('rice'),
  riceOmachi('rice_omachi'),
  rye('rye'),
  sorghum('sorghum'),
  strawberryFruit('strawberry_fruit'),
  sweetPotato('sweet_potato'),
  tropicalFruitMaterial('tropical_fruit_material'),
  waterMaterial('water_material'),
  wheat('wheat'),
  whiteKoji('white_koji'),
  yeast('yeast'),
  yellowKoji('yellow_koji');
  const CatalogIngredientKey(this.key);
  final String key;
  static final _byKey = {for (final v in values) v.key: v};
  static CatalogIngredientKey? fromKey(String key) => _byKey[key];
}

enum CatalogProcessKey {
  americanOak('american_oak'),
  amphoraVessel('amphora_vessel'),
  atmosphericDistillation('atmospheric_distillation'),
  biodynamicCertified('biodynamic_certified'),
  bottleAgeing('bottle_ageing'),
  bottleSecondaryFermentation('bottle_secondary_fermentation'),
  caskFinishing('cask_finishing'),
  caskStrength('cask_strength'),
  charcoalFiltration('charcoal_filtration'),
  charredCask('charred_cask'),
  chillFiltration('chill_filtration'),
  coarseFiltered('coarse_filtered'),
  coldStabilised('cold_stabilised'),
  columnDistillation('column_distillation'),
  concreteVessel('concrete_vessel'),
  culturedFermentation('cultured_fermentation'),
  doubleDistillation('double_distillation'),
  europeanOak('european_oak'),
  exBeerCask('ex_beer_cask'),
  exBourbonCask('ex_bourbon_cask'),
  exBrandyCask('ex_brandy_cask'),
  exPortCask('ex_port_cask'),
  exRumCask('ex_rum_cask'),
  exRyeCask('ex_rye_cask'),
  exSherryCask('ex_sherry_cask'),
  exWineCask('ex_wine_cask'),
  extendedMaturation('extended_maturation'),
  forcedCarbonation('forced_carbonation'),
  fractionalAgeing('fractional_ageing'),
  kimotoStarter('kimoto_starter'),
  maceration('maceration'),
  malolacticFermentation('malolactic_fermentation'),
  mixedCultureFermentation('mixed_culture_fermentation'),
  mizunaraOak('mizunara_oak'),
  multiCaskBlend('multi_cask_blend'),
  multiVintageBlend('multi_vintage_blend'),
  naturalWineClaim('natural_wine_claim'),
  newOakCask('new_oak_cask'),
  nonChillFiltered('non_chill_filtered'),
  oakWood('oak_wood'),
  organicCertified('organic_certified'),
  parallelMultipleFermentation('parallel_multiple_fermentation'),
  pasteurised('pasteurised'),
  peatedMalt('peated_malt'),
  potDistillation('pot_distillation'),
  riceWaterOnlyClaim('rice_water_only_claim'),
  singleCaskMaturation('single_cask_maturation'),
  singleDistillation('single_distillation'),
  smallBatch('small_batch'),
  soleraBlending('solera_blending'),
  spiritFortification('spirit_fortification'),
  spontaneousFermentation('spontaneous_fermentation'),
  stainlessSteelVessel('stainless_steel_vessel'),
  tankSecondaryFermentation('tank_secondary_fermentation'),
  toastedCask('toasted_cask'),
  tripleDistillation('triple_distillation'),
  undiluted('undiluted'),
  unfilteredClaim('unfiltered_claim'),
  unpasteurised('unpasteurised'),
  vacuumDistillation('vacuum_distillation'),
  woodenCask('wooden_cask'),
  yamahaiStarter('yamahai_starter');
  const CatalogProcessKey(this.key);
  final String key;
  static final _byKey = {for (final v in values) v.key: v};
  static CatalogProcessKey? fromKey(String key) => _byKey[key];
}

const catalogAssignmentContract = <String, dynamic>{
  "schema_version": 2,
  "taxonomy_version": "2.0.0",
  "categories": [
    "korean_traditional",
    "sake",
    "whisky",
    "wine"
  ],
  "terms": [
    {
      "kind": "ingredient",
      "key": "apple_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "apricot_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "aronia_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "barley",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "berry_fruit",
      "categories": [
        "korean_traditional",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "blueberry_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "bokbunja_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "buckwheat",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "caramel_colour",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "cherry_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "citrus_fruit",
      "categories": [
        "korean_traditional",
        "sake",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "corn",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "glutinous_rice",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "grape",
      "categories": [
        "korean_traditional",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "hardy_kiwi_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "herb_botanical",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "honey",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "hop_material",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "koji_starter",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "lactic_bacteria",
      "categories": [
        "korean_traditional",
        "sake",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "malted_barley",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "meoru_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "millet",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "mulberry_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "nuruk_starter",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "oat",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "omija_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "peach_fruit",
      "categories": [
        "korean_traditional",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "pear_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "persimmon_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "plum_fruit",
      "categories": [
        "korean_traditional",
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "pomegranate_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "quince_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "rice",
      "categories": [
        "korean_traditional",
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "rice_omachi",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "rye",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "sorghum",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "strawberry_fruit",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "sweet_potato",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "tropical_fruit_material",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "water_material",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "wheat",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "white_koji",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "yeast",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "ingredient",
      "key": "yellow_koji",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "american_oak",
      "categories": [
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "amphora_vessel",
      "categories": [
        "korean_traditional",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "bottle_ageing",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "cask_finishing",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "charred_cask",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "concrete_vessel",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "european_oak",
      "categories": [
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "ex_beer_cask",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "ex_bourbon_cask",
      "categories": [
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "ex_brandy_cask",
      "categories": [
        "sake",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "ex_port_cask",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "ex_rum_cask",
      "categories": [
        "sake",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "ex_rye_cask",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "ex_sherry_cask",
      "categories": [
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "ex_wine_cask",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "extended_maturation",
      "categories": [
        "korean_traditional",
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "fractional_ageing",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "mizunara_oak",
      "categories": [
        "sake",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "new_oak_cask",
      "categories": [
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "oak_wood",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "single_cask_maturation",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "stainless_steel_vessel",
      "categories": [
        "korean_traditional",
        "sake",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "toasted_cask",
      "categories": [
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "maturation",
      "key": "wooden_cask",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "atmospheric_distillation",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "biodynamic_certified",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "bottle_secondary_fermentation",
      "categories": [
        "sake",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "cask_strength",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "charcoal_filtration",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "chill_filtration",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": [
        "non_chill_filtered"
      ]
    },
    {
      "kind": "process",
      "key": "coarse_filtered",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "cold_stabilised",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "column_distillation",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "cultured_fermentation",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "double_distillation",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "forced_carbonation",
      "categories": [
        "korean_traditional",
        "sake",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "kimoto_starter",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "maceration",
      "categories": [
        "korean_traditional",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "malolactic_fermentation",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "mixed_culture_fermentation",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "multi_cask_blend",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "multi_vintage_blend",
      "categories": [
        "sake",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "natural_wine_claim",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "non_chill_filtered",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": [
        "chill_filtration"
      ]
    },
    {
      "kind": "process",
      "key": "organic_certified",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "parallel_multiple_fermentation",
      "categories": [
        "korean_traditional",
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "pasteurised",
      "categories": [
        "korean_traditional",
        "sake",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": [
        "unpasteurised"
      ]
    },
    {
      "kind": "process",
      "key": "peated_malt",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "pot_distillation",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "rice_water_only_claim",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "single_distillation",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "small_batch",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "solera_blending",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "spirit_fortification",
      "categories": [
        "korean_traditional",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "spontaneous_fermentation",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "tank_secondary_fermentation",
      "categories": [
        "sake",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "triple_distillation",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "undiluted",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "unfiltered_claim",
      "categories": [
        "korean_traditional",
        "sake",
        "whisky",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "unpasteurised",
      "categories": [
        "korean_traditional",
        "sake",
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": [
        "pasteurised"
      ]
    },
    {
      "kind": "process",
      "key": "vacuum_distillation",
      "categories": [
        "korean_traditional",
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "process",
      "key": "yamahai_starter",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "american_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "blended_malt_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "blended_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "bourbon",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "corn_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "daiginjo",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "diluted_soju",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "distilled_soju",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "fortified_wine",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "futsushu",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "ginjo",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "grain_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "gwahaju",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "honjozo",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "junmai",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "junmai_daiginjo",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "junmai_ginjo",
      "categories": [
        "sake"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "korean_cheongju",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "korean_fruit_wine",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "madeira_wine",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "orange_wine",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "port_wine",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "red_wine",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "rose_wine",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "rye_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "sherry_wine",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "single_malt_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "single_pot_still_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "sparkling_wine",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "takju",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "tennessee_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "vermouth",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "wheat_whisky",
      "categories": [
        "whisky"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "white_wine",
      "categories": [
        "wine"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    },
    {
      "kind": "style",
      "key": "yakju",
      "categories": [
        "korean_traditional"
      ],
      "styles": [],
      "target": "both",
      "excludes": []
    }
  ],
  "contract_sha256": "af26694d6646a0a6a63c219a74a7a000862ede9372383efed18c26b7e377da5d"
};
