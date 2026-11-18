import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/catalog/catalog_assignment.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/aroma_catalog_input.dart';
import 'package:soolgyul/src/features/onboarding/adaptive/direct_aroma_choices.dart';

import '../support/sensory_fixtures.dart';

void main() {
  final reference = aromaChoiceReference();
  final taxonomy = alcoholTaxonomy();
  final build = aromaEngine;
  final engine = build();
  final adapter = AromaCatalogInputAdapter(
    engine: engine,
    reference: reference,
  );
  Map<String, dynamic> product([Map<String, dynamic> changes = const {}]) => {
    'category': 'korean_traditional',
    'style_key': 'korean_fruit_wine',
    'aroma_keys': <String>[],
    ...changes,
  };
  Set<String> keys(AromaCatalogInput input) =>
      engine.resolve(input.product).ruled.map((o) => o.key).toSet();

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
        'aroma_keys': ['vanilla', 'hazelnut'],
      }),
    );
    final b = adapter.read(
      product({
        'ingredient_keys': [
          'coffee_material',
          'cacao_material',
          'coffee_material',
        ],
        'aroma_keys': ['hazelnut', 'vanilla', 'vanilla'],
      }),
    );
    expect(
      engine.resolve(a.product).ruled.map((o) => o.key),
      engine.resolve(b.product).ruled.map((o) => o.key),
    );
    expect(a.contextSources, b.contextSources);
  });
  test('unused group mistakes and unknown context keys fail closed', () {
    final invalidGroup = deepCopyJson(reference);
    invalidGroup['candidate_groups']['unused'] = {'not_in_dictionary': 50};
    expect(() => build(invalidGroup), throwsFormatException);
    final invalidContext = deepCopyJson(reference);
    invalidContext['catalog_context']['ingredient_contexts']['peach_fruit'] =
        'unknown';
    expect(() => build(invalidContext), throwsFormatException);
  });
  test('adapter holds an immutable copy of its context configuration', () {
    final copy = deepCopyJson(reference);
    final stable = AromaCatalogInputAdapter(engine: engine, reference: copy);
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
        final copy = deepCopyJson(reference);
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
