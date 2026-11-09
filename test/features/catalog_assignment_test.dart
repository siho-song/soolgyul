import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/catalog/catalog_assignment.dart';

void main() {
  final registry = CatalogAssignmentRegistry();
  final cases =
      jsonDecode(
            File(
              'tests/fixtures/catalog_assignment_cases.json',
            ).readAsStringSync(),
          )
          as List;
  for (final row in cases) {
    test('assignment parity: ${row['name']}', () {
      final result = registry.validate(
        Map<String, Object?>.from(row['input'] as Map),
      );
      expect(
        result.issues.map((i) => i.code).toSet().toList()..sort(),
        row['codes'],
      );
      expect(result.value != null, (row['codes'] as List).isEmpty);
    });
  }
  test('validated assignment cannot be modified', () {
    final value = registry.validate({'category_key': 'wine'}).requireValid();
    expect(
      () => value.processKeys.add(CatalogProcessKey.organicCertified),
      throwsUnsupportedError,
    );
    expect(
      () => value.values['production_process_keys'] = [],
      throwsUnsupportedError,
    );
  });
  test('actual catalog keys are enums and wire keys remain unchanged', () {
    final value = registry.validate({
      'category_key': 'wine',
      'style_key': 'red_wine',
      'ingredient_keys': ['grape'],
      'production_process_keys': ['organic_certified'],
    }).requireValid();
    expect(value.categoryKey, CatalogCategoryKey.wine);
    expect(value.styleKey, CatalogStyleKey.redWine);
    expect(value.ingredientKeys, [CatalogIngredientKey.grape]);
    expect(value.processKeys, [CatalogProcessKey.organicCertified]);
    expect(jsonDecode(jsonEncode(value.toJson()))['ingredient_keys'], [
      'grape',
    ]);
    expect(CatalogIngredientKey.fromKey('not_registered'), isNull);
    for (final key in CatalogStyleKey.values) {
      expect(CatalogStyleKey.fromKey(key.key), same(key));
    }
  });
}
