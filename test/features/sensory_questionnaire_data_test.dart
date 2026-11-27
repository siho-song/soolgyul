import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/onboarding_aroma_menu.dart';
import 'package:soolgyul/src/features/onboarding/data/aroma_chip_names.dart';
import 'package:soolgyul/src/features/onboarding/data/sensory_questionnaire_data.dart';

/// Real bundled JSON definitions, without depending on a running Flutter app.
class _RepositoryAssets extends CachingAssetBundle {
  final requested = <String>{};
  String? unavailable;

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    if (key == unavailable) throw StateError('Missing asset: $key');
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}

const _selection = DrinkSelection.catalogMatch(
  CatalogDrink(
    id: 'selected-catalog-id',
    displayName: '선택한 상품',
    // Product classification must come from the public context, not this UI hint.
    category: DrinkCategory.other,
  ),
);

Map<String, dynamic> _context({
  String category = 'wine',
  String? style = 'red_wine',
  List<String> aromas = const [],
  Map<String, dynamic> levels = const {},
}) => {
  'id': _selection.catalogId,
  'name': '상품 문맥 테스트',
  'category': category,
  'style_key': style,
  'target': 'product',
  'ingredient_keys': <String>[],
  'production_process_keys': <String>[],
  'aroma_keys': aromas,
  'texture_keys': <String>[],
  'sensory_scale': 5,
  'levels': levels,
};

void main() {
  late _RepositoryAssets assets;
  setUp(() => assets = _RepositoryAssets());

  Future<SensoryQuestionnaireData> load(Map<String, dynamic>? context) =>
      SensoryQuestionnaireDataSource(
        assets: assets,
        readContext: (id) async {
          expect(id, _selection.catalogId);
          return context;
        },
      ).load(_selection);

  for (final product in [
    (category: 'wine', style: 'red_wine', aromas: ['cherry', 'plum']),
    (category: 'wine', style: 'white_wine', aromas: ['apple', 'pear']),
    (category: 'sake', style: 'junmai', aromas: ['cereal']),
    (category: 'sake', style: 'junmai_ginjo', aromas: ['apple', 'pear']),
    (
      category: 'korean_traditional',
      style: 'takju',
      aromas: ['nuruk', 'cereal'],
    ),
    (
      category: 'korean_traditional',
      style: 'distilled_soju',
      aromas: ['floral', 'cereal'],
    ),
  ]) {
    test(
      '${product.category}/${product.style} loads its menu of offered aromas',
      () async {
        final context = _context(
          category: product.category,
          style: product.style,
          aromas: product.aromas,
        );
        final data = await load(context);
        expect(data.aromaMenu.keys, isNotEmpty);
        expect(data.registry.aromaKeys, containsAll(data.aromaMenu.keys));
        // A flow of the drink's own gauges starts with nothing answered.
        expect(
          data.registry
              .readAnswers(data.registry.createFlow(data.gauges))
              .values,
          everyElement(isEmpty),
        );
      },
    );
  }

  test('the product kind decides which gauges are asked and which aroma '
      'menu is shown', () async {
    List<String> palate(SensoryQuestionnaireData data) => [
      for (final gauge in data.gauges.palate) gauge.axis,
    ];
    final wine = await load(_context(style: 'sparkling_wine'));
    expect(palate(wine), ['sweetness', 'acidity', 'body', 'sparkling']);
    expect(wine.aromaMenu.name, 'wine_white_sparkling_rose');
    final sake = await load(_context(category: 'sake', style: null));
    expect(palate(sake), ['sweetness', 'acidity', 'umami', 'body']);
    expect(sake.aromaMenu.name, 'sake');
    // A kind kept under an older name is asked as the kind it is now.
    final grain = await load(
      _context(category: 'whisky', style: 'single_grain_whisky'),
    );
    expect(palate(grain), ['sweetness', 'body', 'spice', 'peat']);
    expect(grain.aromaMenu.name, 'whisky_malt_blended');
    final bourbon = await load(_context(category: 'whisky', style: 'bourbon'));
    expect(bourbon.aromaMenu.name, 'whisky_american');
    // A kind the app cannot place leaves the category's widest menu.
    // The gauges bound to a kind (타닌) are then not asked.
    final unplaced = await load({..._context(), 'style_key': 'bourbon'});
    expect(unplaced.aromaMenu.name, 'wine_red');
    expect(palate(unplaced), ['sweetness', 'acidity', 'body']);
  });

  test('reading the dictionary names every menu chip by the dictionary\'s '
      'word, for a sheet given an aroma by its name', () async {
    await load(_context());
    final byName = aromaChipByName.value;
    expect(byName['체리']?.picture, 'assets/icons/aromas/cherry.webp');
    expect(byName['붉은 체리'], isNull);
    // No chip is left without a word, and no two share one.
    expect(byName, hasLength(OnboardingAromaMenu.chips.length));
  });

  test('reads the bundled definitions, and every menu chip is an aroma the '
      'dictionary offers', () async {
    final data = await load(_context());
    expect(assets.requested, {
      'catalog/dictionary/senses.json',
      'config/catalog/enrichment_taxonomy_v2.json',
      'catalog/sensory/gauge-definitions.json',
      'catalog/sensory/appearance.json',
    });
    expect(data.registry.aromaKeys, isNotEmpty);
    expect(data.registry.aromaKeys, containsAll(data.aromaMenu.keys));
  });

  test(
    'catalog transport failures propagate instead of returning direct-input defaults',
    () async {
      final error = StateError('catalog unavailable');
      await expectLater(
        SensoryQuestionnaireDataSource(
          assets: assets,
          readContext: (_) async => throw error,
        ).load(_selection),
        throwsA(same(error)),
      );
    },
  );

  test('null and wrong-identity product responses fail closed', () async {
    await expectLater(load(null), throwsFormatException);
    await expectLater(
      load({..._context(), 'id': 'another-product'}),
      throwsFormatException,
    );
  });

  test('an unknown product category fails closed', () async {
    await expectLater(
      load({..._context(), 'category': 'unknown_category'}),
      throwsFormatException,
    );
  });

  test('aroma and style keys this app does not know yet are dropped', () async {
    // The server may add terms after this app shipped; the product is still
    // asked about with what the app knows.
    final data = await load({
      ..._context(aromas: ['cherry', 'new_aroma']),
      'style_key': 'new_style',
      'ingredient_keys': ['new_ingredient'],
      'production_process_keys': ['new_process'],
    });
    // Asked by its category alone: the widest menu, no gauge of a kind.
    expect(data.aromaMenu.name, 'wine_red');
    expect(data.gauges.palate.map((gauge) => gauge.axis), [
      'sweetness',
      'acidity',
      'body',
    ]);
  });

  for (final (change, asked) in <(Map<String, dynamic>, List<String>)>[
    (
      {'category': 'sake', 'style_key': 'red_wine'},
      ['sweetness', 'acidity', 'umami', 'body'],
    ),
    (
      {
        'styles': ['red_wine', 'white_wine'],
      },
      ['sweetness', 'acidity', 'body'],
    ),
  ]) {
    test('a kind this app cannot place is dropped, and the drink is asked '
        'by its category: $change', () async {
      final data = await load({..._context(), ...change});
      expect(data.gauges.palate.map((gauge) => gauge.axis), asked);
    });
  }

  for (final value in <Object?>[null, 1, 100, '5']) {
    test('invalid sensory scale $value fails closed', () async {
      await expectLater(
        load({..._context(), 'sensory_scale': value}),
        throwsFormatException,
      );
    });
  }

  test('a bundled definition that cannot be read fails closed', () async {
    assets.unavailable = 'catalog/dictionary/senses.json';
    final source = SensoryQuestionnaireDataSource(
      assets: assets,
      readContext: (_) async => _context(),
    );
    await expectLater(source.load(_selection), throwsStateError);
  });
}
