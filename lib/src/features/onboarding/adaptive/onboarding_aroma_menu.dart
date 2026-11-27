/// The aroma question's menu: one of nine hand-picked lists, chosen by the
/// drink's category and kind, each a few plain headings over its chips in the
/// order they are shown.
///
/// Every chip stores one dictionary key, so the stored answer and the server's
/// reading of it are the same whichever menu offered it. A chip holds no
/// name: it is drawn under the dictionary's word for its key ("사과" for
/// `apple`), which names the aroma alone, with no word of how it smelled:
/// whether it was sweet or sharp is the drinker's to say.
library;

/// One aroma as a chip draws it: the dictionary key its answer is stored
/// under and the picture that goes before its name.
class OnboardingAromaChip {
  const OnboardingAromaChip(this.key, {required this.picture});

  /// The dictionary key the answer is stored under.
  final String key;

  /// The bundled picture of the aroma.
  final String picture;
}

class OnboardingAromaGroup {
  const OnboardingAromaGroup({required this.title, required this.chips});

  final String title;
  final List<OnboardingAromaChip> chips;
}

class OnboardingAromaMenu {
  const OnboardingAromaMenu._(this.name, this.groups);

  /// The menu of a drink's category and kind. A kind not singled out below,
  /// or no kind, gets its category's widest menu: red wine, malt whisky,
  /// 탁주·약주. An unknown category gets the malt whisky menu, whose words fit
  /// most spirits.
  factory OnboardingAromaMenu.forDrink(String? categoryKey, String? styleKey) {
    final name = switch (categoryKey) {
      'wine' when _paleWines.contains(styleKey) => 'wine_white_sparkling_rose',
      'wine' when _fortifiedWines.contains(styleKey) => 'wine_fortified',
      'wine' => 'wine_red',
      'sake' => 'sake',
      'korean_traditional' => switch (styleKey) {
        // A diluted soju is asked as a soju.
        'distilled_soju' || 'diluted_soju' => 'korean_distilled_soju',
        'korean_fruit_wine' => 'korean_fruit_wine',
        _ => 'korean_takju_yakju',
      },
      'whisky' when _americanWhiskies.contains(styleKey) => 'whisky_american',
      _ => 'whisky_malt_blended',
    };
    return OnboardingAromaMenu._(name, [
      for (final MapEntry(key: title, value: keys) in _menus[name]!.entries)
        OnboardingAromaGroup(
          title: title,
          chips: [for (final key in keys) _chips[key]!],
        ),
    ]);
  }

  /// The chip of [key] as the menus draw it; null for an aroma none of
  /// them holds.
  static OnboardingAromaChip? chipOf(String key) => _chips[key];

  /// Every chip the menus draw, each aroma once.
  static Iterable<OnboardingAromaChip> get chips => _chips.values;

  /// Which of the nine menus this is, such as `wine_red`.
  final String name;
  final List<OnboardingAromaGroup> groups;

  /// What the menu's drinks are called, such as 레드 와인.
  String get label => _labels[name]!;

  Iterable<String> get keys =>
      groups.expand((group) => group.chips).map((chip) => chip.key);

  /// The chips kept behind each heading's first [shown], up to [limit] of
  /// them: the first hidden chip of every heading in menu order, then the
  /// second of every heading, and so on.
  List<OnboardingAromaChip> chipsBeyond(int shown, {required int limit}) {
    final longest = groups.fold(
      0,
      (length, group) =>
          group.chips.length > length ? group.chips.length : length,
    );
    return [
      for (var place = shown; place < longest; place++)
        for (final group in groups)
          if (place < group.chips.length) group.chips[place],
    ].take(limit).toList();
  }

  static const _labels = {
    'wine_red': '레드 와인',
    'wine_white_sparkling_rose': '화이트·스파클링·로제 와인',
    'wine_fortified': '주정강화 와인',
    'whisky_malt_blended': '위스키',
    'whisky_american': '버번·라이 위스키',
    'sake': '사케',
    'korean_takju_yakju': '탁주·약주',
    'korean_distilled_soju': '증류식 소주',
    'korean_fruit_wine': '과실주',
  };

  static const _paleWines = {
    'white_wine',
    'sparkling_wine',
    'rose_wine',
    'orange_wine',
  };

  static const _fortifiedWines = {
    'fortified_wine',
    'port_wine',
    'sherry_wine',
    'madeira_wine',
    'vermouth',
  };

  static const _americanWhiskies = {
    'bourbon',
    'rye_whisky',
    'tennessee_whisky',
    'corn_whisky',
    'wheat_whisky',
    'american_whisky',
  };

  /// Each menu's headings, in order, over the dictionary keys of their chips.
  static const _menus = <String, Map<String, List<String>>>{
    'wine_red': {
      '과일': [
        'blackberry',
        'blackcurrant',
        'raspberry',
        'blueberry',
        'cranberry',
        'strawberry',
        'black_cherry',
        'cherry',
        'plum',
        'pomegranate',
        'jammy',
        'orange',
        'fresh_fig',
        'dried_fig',
        'raisin',
        'prune',
      ],
      '꽃·허브': [
        'rose',
        'red_flower',
        'violet',
        'lavender',
        'herbal',
        'rosemary',
        'mint',
        'eucalyptus',
        'grass',
        'hay',
        'tomato',
        'black_tea',
      ],
      '달콤·견과': [
        'vanilla',
        'honey',
        'caramel',
        'brown_sugar',
        'dark_chocolate',
        'milk_chocolate',
        'cocoa',
        'mocha',
        'coffee',
        'almond',
        'hazelnut',
        'walnut',
      ],
      '오크·스파이스': [
        'oak',
        'cedar',
        'sandalwood',
        'toast',
        'roasted',
        'cinnamon',
        'clove',
        'nutmeg',
        'pepper',
        'liquorice',
        'smoke',
        'tobacco',
        'leather',
        'earth',
        'mushroom',
        'mineral',
        'wet_stone',
        'fermentation',
        'savory',
        'olive',
      ],
    },
    'wine_white_sparkling_rose': {
      '과일': [
        'raspberry',
        'cranberry',
        'strawberry',
        'cherry',
        'pomegranate',
        'lemon',
        'lime',
        'yuzu',
        'grapefruit',
        'orange',
        'tangerine_mandarin',
        'apple',
        'green_apple',
        'pear',
        'quince',
        'peach',
        'apricot',
        'dried_apricot',
        'grape',
        'green_grape',
        'melon',
        'watermelon',
        'pineapple',
        'mango',
        'passion_fruit',
        'lychee',
        'kiwi',
        'candy',
      ],
      '꽃·허브': [
        'white_flower',
        'acacia',
        'jasmine',
        'chamomile',
        'rose',
        'herbal',
        'mint',
        'grass',
        'hay',
        'green_tea',
        'earl_grey',
        'sandalwood',
        'pepper',
        'ginger',
      ],
      '달콤·빵': [
        'vanilla',
        'honey',
        'custard',
        'creme_brulee',
        'brioche',
        'toast',
        'butter',
        'cream',
        'cheese',
        'almond',
        'hazelnut',
        'cashew',
      ],
      '미네랄·발효': [
        'yeast',
        'oak',
        'earth',
        'mineral',
        'wet_stone',
        'saline',
        'fermentation',
      ],
    },
    'wine_fortified': {
      '과일': [
        'blackberry',
        'plum',
        'orange',
        'marmalade',
        'apple',
        'pear',
        'dried_apricot',
        'fresh_fig',
        'dried_fig',
        'raisin',
        'prune',
      ],
      '달콤·견과': [
        'vanilla',
        'honey',
        'caramel',
        'toffee',
        'brown_sugar',
        'dark_chocolate',
        'milk_chocolate',
        'mocha',
        'coffee',
        'almond',
        'hazelnut',
        'walnut',
        'pecan',
      ],
      '오크·숙성': [
        'oak',
        'cinnamon',
        'clove',
        'nutmeg',
        'liquorice',
        'smoke',
        'tobacco',
        'leather',
        'fermentation',
      ],
    },
    'whisky_malt_blended': {
      '과일·꽃': [
        'cherry',
        'plum',
        'lemon',
        'orange',
        'tangerine_mandarin',
        'marmalade',
        'apple',
        'green_apple',
        'pear',
        'peach',
        'apricot',
        'dried_apricot',
        'banana',
        'pineapple',
        'coconut',
        'fresh_fig',
        'dried_fig',
        'raisin',
        'prune',
        'herbal',
        'mint',
        'grass',
      ],
      '달콤·디저트': [
        'vanilla',
        'honey',
        'caramel',
        'toffee',
        'brown_sugar',
        'maple_syrup',
        'custard',
        'creme_brulee',
        'dark_chocolate',
        'milk_chocolate',
        'cocoa',
        'mocha',
        'coffee',
        'sherry',
        'toast',
        'roasted',
        'butter',
      ],
      '오크·곡물': [
        'malt',
        'barley',
        'wheat',
        'oak',
        'cedar',
        'sandalwood',
        'almond',
        'hazelnut',
        'walnut',
        'pecan',
        'peanut',
      ],
      '스모키·스파이스': [
        'cinnamon',
        'clove',
        'nutmeg',
        'pepper',
        'ginger',
        'liquorice',
        'smoke',
        'peat',
        'tobacco',
        'leather',
        'mineral',
        'wet_stone',
        'saline',
      ],
    },
    'whisky_american': {
      '달콤·디저트': [
        'vanilla',
        'honey',
        'caramel',
        'toffee',
        'brown_sugar',
        'maple_syrup',
        'custard',
        'creme_brulee',
        'dark_chocolate',
        'cocoa',
        'butter',
      ],
      '오크·곡물': [
        'corn',
        'oak',
        'cedar',
        'toast',
        'roasted',
        'almond',
        'hazelnut',
        'walnut',
        'pecan',
        'peanut',
        'smoke',
      ],
      '과일·꽃': [
        'cherry',
        'orange',
        'apple',
        'peach',
        'banana',
        'coconut',
        'fresh_fig',
        'raisin',
        'prune',
        'white_flower',
        'rose',
        'lavender',
      ],
      '스파이스·허브': [
        'herbal',
        'mint',
        'cinnamon',
        'clove',
        'nutmeg',
        'pepper',
        'ginger',
        'liquorice',
        'tobacco',
        'leather',
      ],
    },
    'sake': {
      '과일': [
        'strawberry',
        'plum',
        'lemon',
        'lime',
        'grapefruit',
        'apple',
        'green_apple',
        'pear',
        'peach',
        'apricot',
        'grape',
        'green_grape',
        'melon',
        'korean_melon',
        'watermelon',
        'banana',
        'pineapple',
        'mango',
        'lychee',
        'candy',
      ],
      '쌀·달콤': [
        'rice',
        'scorched_rice',
        'barley',
        'wheat',
        'honey',
        'cream',
        'cheese',
        'almond',
        'chestnut',
        'sesame',
      ],
      '꽃·허브': [
        'white_flower',
        'acacia',
        'jasmine',
        'cherry_plum_blossom',
        'herbal',
        'grass',
        'ginger',
        'mushroom',
        'mineral',
        'wet_stone',
      ],
      '발효·감칠맛': ['nuruk', 'yeast', 'fermentation', 'savory'],
    },
    'korean_takju_yakju': {
      '쌀·발효': [
        'rice',
        'scorched_rice',
        'nuruk',
        'yeast',
        'barley',
        'wheat',
        'corn',
        'cream',
        'lactic',
        'fermentation',
      ],
      '과일': [
        'omija_bokbunja',
        'strawberry',
        'plum',
        'yuzu',
        'tangerine_mandarin',
        'apple',
        'green_apple',
        'pear',
        'quince',
        'peach',
        'apricot',
        'grape',
        'green_grape',
        'melon',
        'korean_melon',
        'watermelon',
        'banana',
        'jujube',
        'ume',
      ],
      '꽃·약초': [
        'white_flower',
        'acacia',
        'cherry_plum_blossom',
        'chamomile',
        'herbal',
        'mint',
        'medicinal_herb',
        'mugwort',
        'pine',
        'grass',
        'green_tea',
        'cinnamon',
        'ginger',
        'liquorice',
        'mushroom',
      ],
      '달콤·견과': [
        'vanilla',
        'honey',
        'caramel',
        'brown_sugar',
        'walnut',
        'peanut',
        'chestnut',
        'sesame',
      ],
    },
    'korean_distilled_soju': {
      '쌀·발효': [
        'rice',
        'scorched_rice',
        'nuruk',
        'barley',
        'wheat',
        'corn',
        'toast',
        'roasted',
        'almond',
        'peanut',
        'chestnut',
        'sesame',
      ],
      '과일·꽃': [
        'lemon',
        'yuzu',
        'tangerine_mandarin',
        'apple',
        'green_apple',
        'pear',
        'peach',
        'grape',
        'melon',
        'ume',
        'white_flower',
        'acacia',
        'cherry_plum_blossom',
      ],
      '오크·달콤': [
        'vanilla',
        'honey',
        'caramel',
        'brown_sugar',
        'maple_syrup',
        'dark_chocolate',
        'cocoa',
        'coffee',
        'oak',
        'cedar',
        'sandalwood',
        'smoke',
      ],
      '약초·스파이스': [
        'herbal',
        'mint',
        'medicinal_herb',
        'pine',
        'grass',
        'cinnamon',
        'nutmeg',
        'pepper',
        'ginger',
        'liquorice',
        'earth',
        'mineral',
        'wet_stone',
        'savory',
      ],
    },
    'korean_fruit_wine': {
      '과일': [
        'omija_bokbunja',
        'blackberry',
        'raspberry',
        'blueberry',
        'cranberry',
        'strawberry',
        'cherry',
        'plum',
        'pomegranate',
        'jammy',
        'lemon',
        'yuzu',
        'orange',
        'tangerine_mandarin',
        'apple',
        'pear',
        'quince',
        'peach',
        'apricot',
        'grape',
        'green_grape',
        'fresh_fig',
        'raisin',
        'jujube',
        'ume',
      ],
      '꽃·스파이스': [
        'white_flower',
        'acacia',
        'cherry_plum_blossom',
        'chamomile',
        'rose',
        'lavender',
        'herbal',
        'mint',
        'medicinal_herb',
        'mugwort',
        'pine',
        'clove',
        'pepper',
        'ginger',
      ],
      '달콤·오크': [
        'vanilla',
        'honey',
        'caramel',
        'brown_sugar',
        'oak',
        'cinnamon',
        'fermentation',
      ],
    },
  };

  /// `assets/icons/aromas/` holds a picture, named by its key, for every
  /// aroma the menus draw.
  static final _chips = <String, OnboardingAromaChip>{
    for (final key in {
      for (final menu in _menus.values) ...menu.values.expand((keys) => keys),
    })
      key: OnboardingAromaChip(key, picture: 'assets/icons/aromas/$key.webp'),
  };
}
