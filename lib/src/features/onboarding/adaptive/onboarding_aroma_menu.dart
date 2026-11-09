/// The first record's aroma menu: a hand-picked, fixed list per drink
/// category, four chips under each of four plain headings. The app's record flow keeps
/// the ranked engine list, "향 더 보기" and search.
///
/// Every chip stores one dictionary key, so the stored answer and the server's
/// reading of it are the same as in the record flow. Only the words on the
/// screen differ: a beginner reads "달콤한 사과·배", the answer stores `apple`.
library;

class OnboardingAromaChip {
  const OnboardingAromaChip(this.key, this.emoji, this.label);

  /// Emoji come from the device's own font, so the menu uses only emoji
  /// released by 2018 (Unicode 11); newer ones show as boxes on older
  /// Android and Windows 10 browsers.

  /// The dictionary key stored as `notice:aroma:<key>`.
  final String key;
  final String emoji;

  /// What the chip calls this aroma.
  final String label;
}

class OnboardingAromaGroup {
  const OnboardingAromaGroup({required this.title, required this.chips});

  final String title;
  final List<OnboardingAromaChip> chips;
}

class OnboardingAromaMenu {
  const OnboardingAromaMenu._(this.groups);

  /// The menu of a drink category; unknown categories get the whisky menu,
  /// whose words fit most spirits.
  factory OnboardingAromaMenu.forCategory(String? categoryKey) =>
      OnboardingAromaMenu._(_groups(_keysByCategory[categoryKey] ?? _whisky));

  final List<OnboardingAromaGroup> groups;

  Iterable<String> get keys =>
      groups.expand((group) => group.chips).map((chip) => chip.key);

  static List<OnboardingAromaGroup> _groups(List<List<String>> keysByGroup) => [
    for (final (index, keys) in keysByGroup.indexed)
      OnboardingAromaGroup(
        title: _groupTitles[index],
        chips: [for (final key in keys) _chips[key]!],
      ),
  ];

  static const _groupTitles = <String>[
    '상큼·달콤 과일',
    '은은·포근 달콤함',
    '풀·꽃·자연',
    '개성 강한 스파이스·스모키',
  ];

  /// Each category lists its keys in the order of [_groupTitles].
  static const _keysByCategory = <String, List<List<String>>>{
    'whisky': _whisky,
    'wine': [
      ['lemon_lime', 'cherry', 'berry', 'peach'],
      ['vanilla', 'mocha', 'oak', 'honey'],
      ['floral', 'herbal', 'earth', 'tea'],
      ['smoke', 'pepper', 'spice', 'mint'],
    ],
    'sake': [
      ['apple', 'melon', 'banana', 'peach'],
      ['dairy', 'honey', 'nutty', 'candy'],
      ['floral', 'herbal', 'rice', 'cereal'],
      ['nuruk', 'fermentation', 'saline', 'spice'],
    ],
    'korean_traditional': [
      ['apple', 'berry', 'peach', 'lemon_lime'],
      ['dairy', 'honey', 'nutty', 'caramel'],
      ['floral', 'herbal', 'rice', 'cereal'],
      ['nuruk', 'fermentation', 'spice', 'medicinal_herb'],
    ],
  };

  static const _whisky = <List<String>>[
    ['lemon_lime', 'apple', 'dried_fruit', 'peach'],
    ['vanilla', 'mocha', 'oak', 'honey'],
    ['floral', 'herbal', 'cereal', 'earth'],
    ['smoke', 'pepper', 'spice', 'mint'],
  ];

  static const _chips = <String, OnboardingAromaChip>{
    'lemon_lime': OnboardingAromaChip('lemon_lime', '🍋', '상큼한 레몬·라임'),
    'apple': OnboardingAromaChip('apple', '🍎', '달콤한 사과·배'),
    'cherry': OnboardingAromaChip('cherry', '🍒', '새콤한 체리'),
    'berry': OnboardingAromaChip('berry', '🍓', '짙은 베리류'),
    'peach': OnboardingAromaChip('peach', '🍑', '잘 익은 복숭아'),
    'dried_fruit': OnboardingAromaChip('dried_fruit', '🍇', '달콤한 말린 과일'),
    'melon': OnboardingAromaChip('melon', '🍈', '시원한 멜론·참외'),
    'banana': OnboardingAromaChip('banana', '🍌', '달콤한 바나나'),
    'vanilla': OnboardingAromaChip('vanilla', '🍦', '부드러운 바닐라'),
    'mocha': OnboardingAromaChip('mocha', '🍫', '진한 초콜릿·커피'),
    'oak': OnboardingAromaChip('oak', '🌳', '묵직한 나무·오크'),
    'honey': OnboardingAromaChip('honey', '🍯', '달큰한 꿀'),
    'caramel': OnboardingAromaChip('caramel', '🍮', '달콤한 캐러멜'),
    'candy': OnboardingAromaChip('candy', '🍬', '달콤한 캔디'),
    'dairy': OnboardingAromaChip('dairy', '🥛', '부드러운 크림'),
    'nutty': OnboardingAromaChip('nutty', '🥜', '고소한 견과'),
    'floral': OnboardingAromaChip('floral', '🌸', '화사한 꽃 향'),
    'herbal': OnboardingAromaChip('herbal', '🌿', '싱그러운 풀·허브'),
    'cereal': OnboardingAromaChip('cereal', '🌾', '구수한 곡물'),
    'rice': OnboardingAromaChip('rice', '🍚', '구수한 쌀'),
    'earth': OnboardingAromaChip('earth', '🍂', '차분한 흙 내음'),
    'tea': OnboardingAromaChip('tea', '🍵', '은은한 찻잎'),
    'medicinal_herb': OnboardingAromaChip('medicinal_herb', '🍃', '쌉싸름한 약초'),
    'saline': OnboardingAromaChip('saline', '🌊', '짭짤한 바닷바람'),
    'smoke': OnboardingAromaChip('smoke', '💨', '훈연·스모키'),
    'pepper': OnboardingAromaChip('pepper', '🌶️', '톡 쏘는 후추'),
    'spice': OnboardingAromaChip('spice', '🧂', '포근한 향신료'),
    'mint': OnboardingAromaChip('mint', '🌱', '알싸한 민트'),
    'nuruk': OnboardingAromaChip('nuruk', '🍙', '은은한 누룩·코지'),
    'fermentation': OnboardingAromaChip('fermentation', '🍶', '새콤한 발효 향'),
  };
}
