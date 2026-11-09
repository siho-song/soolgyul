import 'sensory_question_flow.dart';

/// Which tastes and mouthfeel choices a kind is asked, after the WSET
/// systematic approach to tasting: a wine is tasted for sweetness and acidity
/// (bitterness is read through tannin), tannin is asked only where there is
/// some, as its two ends (drying / smooth), and the mousse (탄산) only where
/// the kind traps its gas: sparkling wine and 탁주. Whisky is not tasted for
/// acidity. A traditional bottle of unknown kind may be a 탁주, so it keeps
/// the 탄산 row; a drink without a catalog product keeps every choice.
class SensoryAskedKeys {
  const SensoryAskedKeys(this.tasteKeys, this.mouthfeelKeys);

  final Set<String> tasteKeys;
  final Set<String> mouthfeelKeys;

  static const all = SensoryAskedKeys(
    SensoryQuestionFlow.tasteKeys,
    SensoryQuestionFlow.mouthfeelKeys,
  );

  static const _tanninWines = {'red_wine', 'orange_wine', 'port_wine'};

  /// The kinds whose carbonation the dictionary does not put at none.
  static const _carbonated = {'sparkling_wine', 'takju'};

  /// Every mouthfeel row but 탄산.
  static const _still = {'light', 'heavy', 'smooth', 'drying', 'warmth'};

  factory SensoryAskedKeys.forProduct(String categoryKey, String? styleKey) =>
      switch (categoryKey) {
        // Vermouth is bittered with wormwood, so its bitterness stays asked.
        'wine' => SensoryAskedKeys(
          {'sweetness', 'acidity', if (styleKey == 'vermouth') 'bitterness'},
          {
            'light',
            'heavy',
            if (_tanninWines.contains(styleKey)) ...{'smooth', 'drying'},
            if (_carbonated.contains(styleKey)) 'bubbles',
            'warmth',
          },
        ),
        'whisky' => const SensoryAskedKeys({'sweetness', 'bitterness'}, _still),
        'sake' => const SensoryAskedKeys(SensoryQuestionFlow.tasteKeys, _still),
        'korean_traditional' =>
          styleKey == null || _carbonated.contains(styleKey)
              ? all
              : const SensoryAskedKeys(SensoryQuestionFlow.tasteKeys, _still),
        _ => all,
      };
}
