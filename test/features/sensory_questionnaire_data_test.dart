import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/catalog/data/catalog_drink.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/direct_aroma_choices.dart';
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
      '${product.category}/${product.style} loads 8..10 options from real rules',
      () async {
        final context = _context(
          category: product.category,
          style: product.style,
          aromas: product.aromas,
        );
        if (product.style == 'distilled_soju') {
          context['ingredient_keys'] = ['rice'];
        }
        final data = await load(context);
        expect(data.aromas.status, AromaChoiceStatus.ready);
        expect(data.aromas.options, hasLength(10));
        expect(
          data.aromas.options.map((option) => option.key).toSet().length,
          data.aromas.options.length,
        );
        expect(
          data.aromas.options.every(
            (option) => data.registry.aromaKeys.contains(option.key),
          ),
          isTrue,
        );
        expect(
          data.aromas.productKeys,
          product.aromas
              .map(data.aromaEngine.representativeFor)
              .whereType<String>()
              .toSet(),
        );
        expect(data.registry.readAnswers(data.registry.createFlow()), isEmpty);
      },
    );
  }

  test(
    'the product kind decides which tastes and mouthfeel are asked',
    () async {
      final wine = await load(_context(style: 'sparkling_wine'));
      expect(wine.asked.tasteKeys, {'sweetness', 'acidity'});
      expect(wine.asked.mouthfeelKeys, {'light', 'heavy', 'bubbles', 'warmth'});
      final sake = await load(_context(category: 'sake', style: null));
      expect(sake.asked.tasteKeys, hasLength(3));
    },
  );

  test(
    'sparse distilled product still shows ten options without inventing rice',
    () async {
      final data = await load(
        _context(
          category: 'korean_traditional',
          style: 'distilled_soju',
          aromas: ['floral', 'cereal'],
        ),
      );
      expect(data.aromas.status, AromaChoiceStatus.ready);
      expect(data.aromas.options, hasLength(10));
      expect(data.aromas.options.take(2).map((o) => o.key).toSet(), {
        'floral',
        'cereal',
      });
      expect(data.aromas.productKeys, {'floral', 'cereal'});
      expect(
        data.aromaEngine.search('사과').map((option) => option.key),
        contains('apple'),
      );
    },
  );

  test(
    'uses bundled definitions and leaves the full dictionary searchable',
    () async {
      final data = await load(_context());
      expect(assets.requested, {
        'catalog/sensory/aroma-choice-reference.json',
        'catalog/dictionary/terms.json',
        'catalog/sensory/palate-question-bank.json',
        'catalog/sensory/answer-option-definitions.json',
      });
      expect(data.registry.aromaKeys, isNotEmpty);
      expect(data.aromaEngine.selectableKeys, data.registry.aromaKeys);
      for (final key in data.registry.aromaKeys) {
        final label = data.registry.lookup('notice:aroma:$key').label;
        expect(
          data.aromaEngine.search(label).map((option) => option.key),
          contains(key),
          reason: label,
        );
      }
      expect(data.aromas.productKeys, isEmpty);
      expect(
        data.aromas.options.every((option) => !option.productListed),
        isTrue,
      );
    },
  );

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

  for (final change in <Map<String, dynamic>>[
    {'category': 'unknown_category'},
    {'style_key': 'unknown_style'},
    {'category': 'sake', 'style_key': 'red_wine'},
    {
      'styles': ['red_wine', 'white_wine'],
    },
    {
      'production_process_keys': ['unknown_process'],
    },
    {
      'aroma_keys': ['unknown_aroma'],
    },
  ]) {
    test(
      'invalid classification or product aroma fails closed: $change',
      () async {
        await expectLater(
          load({..._context(), ...change}),
          throwsFormatException,
        );
      },
    );
  }

  for (final value in <Object?>[null, 1, 100, '5']) {
    test('invalid sensory scale $value fails closed', () async {
      await expectLater(
        load({..._context(), 'sensory_scale': value}),
        throwsFormatException,
      );
    });
  }

  test(
    'missing bundled rules fail closed for catalog and direct input alike',
    () async {
      assets.unavailable = 'catalog/sensory/aroma-choice-reference.json';
      final source = SensoryQuestionnaireDataSource(
        assets: assets,
        readContext: (_) async => _context(),
      );
      await expectLater(source.load(_selection), throwsStateError);
    },
  );
}
