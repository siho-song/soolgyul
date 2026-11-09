import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/catalog/catalog_assignment.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/aroma_catalog_input.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/direct_aroma_choices.dart';
import 'package:soolgyul/src/features/onboarding/data/dictionary_views.dart';

Map<String, dynamic> read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final reference = read('catalog/sensory/aroma-choice-reference.json');
  final vocabulary = serviceVocabularyView(
    read('catalog/dictionary/terms.json'),
  );
  final source = sensoryCatalogView(read('catalog/dictionary/terms.json'));
  final taxonomy = taxonomyView(read('catalog/dictionary/terms.json'));
  DirectAromaChoiceEngine build([Map<String, dynamic>? ref]) =>
      DirectAromaChoiceEngine(
        reference: ref ?? reference,
        vocabulary: vocabulary,
        sourceCatalog: source,
        alcoholTaxonomy: taxonomy,
      );
  final engine = build();
  final adapter = AromaCatalogInputAdapter(
    engine: engine,
    reference: reference,
    vocabulary: vocabulary,
    sourceCatalog: source,
  );
  Map<String, dynamic> product([Map<String, dynamic> changes = const {}]) => {
    'category': 'korean_traditional',
    'style_key': 'korean_fruit_wine',
    'aroma_keys': <String>[],
    ...changes,
  };
  Map<String, dynamic> note([Map<String, dynamic> changes = const {}]) => {
    'id': 'source-profile',
    'origin': 'verified',
    'source_url': 'https://example.test/product',
    'note': '바닐라, 초콜릿, 커피',
    ...changes,
  };
  Set<String> keys(AromaCatalogInput input) =>
      engine.resolve(input.product).ruled.map((o) => o.key).toSet();

  test('verified source aroma prose restores missing descriptors only', () {
    final row = product({
      'aroma_keys': ['coffee', 'vanilla'],
      'aroma_notes': [note()],
      'flavor_notes': '체리',
      'memo': '사과',
    });
    final before = jsonEncode(row);
    final input = adapter.read(row);
    expect(input.recoveredAromaKeys, {'chocolate'});
    expect(engine.resolve(input.product).productKeys, {
      'coffee',
      'vanilla',
      'chocolate',
    });
    expect(jsonEncode(row), before);
  });

  for (final rejected in [
    {'origin': 'estimated'},
    {'origin': 'editorial'},
    {'source_url': ''},
    {'source_url': 'urn:legacy'},
    {'review_status': 'rejected'},
    {'publish_status': 'withdrawn'},
    {'alcohol_release_id': 'another-release'},
    {'note': '초콜릿, 커피 향은 없어요'},
    {'note': 'No chocolate or coffee'},
    {'note': '커피 맛과 초콜릿 여운'},
    {'note': '커피를 원료로 사용; 초콜릿 칵테일 페어링'},
  ]) {
    test('does not recover unsafe or wrong-phase note: $rejected', () {
      expect(
        adapter
            .read(
              product({
                'aroma_notes': [note(rejected)],
              }),
            )
            .recoveredAromaKeys,
        isEmpty,
      );
    });
  }

  test('long aliases win without turning green tea into several facts', () {
    final input = adapter.read(
      product({
        'aroma_notes': [
          note({'note': '녹차 향; green apple; black cherry'}),
        ],
      }),
    );
    expect(input.recoveredAromaKeys, {'green_tea', 'green_apple', 'cherry'});
  });

  test('new aroma sources use existing representatives and preserve musk', () {
    final input = adapter.read(
      product({
        'aroma_notes': [
          note({'note': '시더우드, 블러드 오렌지, 밀싹, 커스터드, 슬레이트, 사향'}),
        ],
      }),
    );
    expect(input.recoveredAromaKeys, {
      'wood',
      'orange_tangerine',
      'leaf',
      'dessert_aromatic',
      'wet_stone',
      'musk',
    });
  });

  test('musk melon never creates an independent musk aroma', () {
    for (final text in [
      '머스크 멜론',
      '머스크멜론',
      '머스크 메론',
      '머스크(멜론)',
      '머스크-멜론',
      'musk melon',
      'musk(melon)',
      'muskmelon',
      'Muscat',
    ]) {
      final input = adapter.read(
        product({
          'aroma_notes': [
            note({'note': text}),
          ],
        }),
      );
      expect(input.recoveredAromaKeys, isNot(contains('musk')), reason: text);
    }
    final input = adapter.read(
      product({
        'aroma_notes': [
          note({'note': '머스크 멜론, 은은한 머스크향'}),
        ],
      }),
    );
    expect(input.recoveredAromaKeys, contains('musk'));
  });
  test('ingredient selects suggestions but never becomes an aroma fact', () {
    final input = adapter.read(
      product({
        'ingredient_keys': ['peach_fruit'],
        'aroma_keys': ['fruit'],
      }),
    );
    final result = engine.resolve(input.product);
    expect(result.hasEnoughOptions, isTrue);
    expect(result.ruled.first.key, 'peach');
    expect(result.productKeys, isEmpty);
    expect(input.recoveredAromaKeys, isEmpty);
    expect(input.contextSources['peach'], {'ingredient:peach_fruit'});
  });
  test('missing style can use explicit flavor without inventing a style', () {
    final input = adapter.read(
      product({'style_key': null, 'name': '복숭아향 테스트'}),
    );
    expect(input.product.styleKeys, isEmpty);
    expect(input.product.aromaKeys, isEmpty);
    expect(keys(input), contains('peach'));
    expect(engine.resolve(input.product).hasEnoughOptions, isTrue);
  });
  test('name cue does not match an unscoped kind or arbitrary name', () {
    for (final row in [
      {'category': 'sake', 'style_key': 'junmai', 'name': 'Apple Neutral'},
      {'category': 'wine', 'style_key': 'red_wine', 'name': 'Peach Estate'},
      {'style_key': null, 'name': 'Pineappleton House'},
    ]) {
      expect(adapter.read(product(row)).product.contextKeys, isEmpty);
    }
  });
  test('direct and catalog entry points interpret aroma contexts alike', () {
    final input = adapter.read(
      product({
        'aroma_keys': ['mint'],
      }),
    );
    final direct = engine.resolve(
      AromaProductContext(
        categoryKey: 'korean_traditional',
        styleKeys: ['korean_fruit_wine'],
        aromaKeys: ['mint'],
      ),
    );
    expect(keys(input), direct.ruled.map((o) => o.key).toSet());
    expect(direct.hasEnoughOptions, isTrue);
    expect(keys(input), isNot(contains('clove')));
  });
  test('duplicates and source order do not alter the shortlist', () {
    final a = adapter.read(
      product({
        'ingredient_keys': ['cacao_material', 'coffee_material'],
        'aroma_notes': [
          note(),
          note({'note': '헤이즐넛'}),
        ],
      }),
    );
    final b = adapter.read(
      product({
        'ingredient_keys': [
          'coffee_material',
          'cacao_material',
          'coffee_material',
        ],
        'aroma_notes': [
          note({'note': '헤이즐넛'}),
          note(),
          note(),
        ],
      }),
    );
    expect(
      engine.resolve(a.product).ruled.map((o) => o.key),
      engine.resolve(b.product).ruled.map((o) => o.key),
    );
    expect(a.recoveredAromaKeys, b.recoveredAromaKeys);
  });
  test('unused group mistakes and unknown context keys fail closed', () {
    final invalidGroup =
        jsonDecode(jsonEncode(reference)) as Map<String, dynamic>;
    invalidGroup['candidate_groups']['unused'] = {'not_in_dictionary': 50};
    expect(() => build(invalidGroup), throwsFormatException);
    final invalidContext =
        jsonDecode(jsonEncode(reference)) as Map<String, dynamic>;
    invalidContext['catalog_context']['ingredient_contexts']['peach_fruit'] =
        'unknown';
    expect(() => build(invalidContext), throwsFormatException);
  });
  test('adapter holds an immutable copy of its context configuration', () {
    final copy = jsonDecode(jsonEncode(reference)) as Map<String, dynamic>;
    final stable = AromaCatalogInputAdapter(
      engine: engine,
      reference: copy,
      vocabulary: vocabulary,
      sourceCatalog: source,
    );
    copy['catalog_context']['ingredient_contexts']['peach_fruit'] = 'coffee';
    final row = product({
      'ingredient_keys': ['peach_fruit'],
    });
    expect(stable.read(row).product.contextKeys, {'peach'});
    expect(
      () => (stable.config['ingredient_contexts'] as Map).clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'process context configuration rejects unknown process and context keys',
    () {
      for (final mapping in [
        {'not_a_process': 'wood_maturation'},
        {'wooden_cask': 'not_a_context'},
      ]) {
        final copy = jsonDecode(jsonEncode(reference)) as Map<String, dynamic>;
        copy['catalog_context']['process_contexts'] = mapping;
        expect(() => build(copy), throwsFormatException);
      }
    },
  );
  test('every registered style yields bounded, known, distinct choices', () {
    final categories = {
      for (final r in taxonomy['primary_styles'] as List)
        r['style_key'] as String: r['category_key'] as String,
    };
    expect(
      categories.keys.toSet(),
      CatalogStyleKey.values.map((v) => v.key).toSet(),
    );
    for (final entry in categories.entries) {
      for (final aromas in [
        <String>[],
        ['apple', 'orange', 'vanilla'],
      ]) {
        final result = engine
            .resolve(
              AromaProductContext(
                categoryKey: entry.value,
                styleKeys: [entry.key],
                aromaKeys: aromas,
              ),
            )
            .options
            .map((o) => o.key)
            .toList();
        expect(result.length, 10);
        expect(result.toSet().length, result.length);
        expect(engine.selectableKeys.containsAll(result), isTrue);
      }
    }
  });
}

/// Rule coverage only: product-listed or rule-backed options, ignoring the
/// related-aroma fill that always pads the visible list.
extension on DirectAromaResolution {
  List<DirectAromaOption> get ruled => [
    ...options,
    ...moreOptions,
  ].where((o) => o.productListed || o.ruleIds.isNotEmpty).toList();
  bool get hasEnoughOptions => ruled.length >= 8;
}
