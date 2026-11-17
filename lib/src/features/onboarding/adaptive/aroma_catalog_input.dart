import 'direct_aroma_choices.dart';
import '../../../core/catalog/catalog_assignment.dart';

Object? _freezeConfig(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freezeConfig(entry.value),
    });
  }
  if (value is List) return List.unmodifiable(value.map(_freezeConfig));
  return value;
}

/// Local catalog adapter. A bottle's aromas are the tags the catalog sends;
/// no note text is read for more. Never reads a user's memo or writes catalog
/// facts.
class AromaCatalogInput {
  AromaCatalogInput({required this.product, required this.contextSources});

  final AromaProductContext product;
  final Map<String, Set<String>> contextSources;
}

class AromaCatalogInputAdapter {
  AromaCatalogInputAdapter({
    required this.engine,
    required Map<String, dynamic> reference,
  }) : config =
           _freezeConfig(reference['catalog_context'] ?? {})
               as Map<String, dynamic>;

  final DirectAromaChoiceEngine engine;
  final Map<String, dynamic> config;

  AromaCatalogInput read(Map<String, dynamic> row) {
    List<String> list(Object? value) => List<String>.from(value as List? ?? []);
    final category = row['category'] as String;
    final styles = row['styles'] != null
        ? list(row['styles'])
        : [if (row['style_key'] is String) row['style_key'] as String];
    final aromas = list(row['aroma_keys']).toSet();
    final contextSources = <String, Set<String>>{};
    void add(Object? context, String source) {
      if (context is String) {
        contextSources.putIfAbsent(context, () => <String>{}).add(source);
      }
    }

    final ingredientContexts = config['ingredient_contexts'] as Map? ?? {};
    for (final key in list(row['ingredient_keys'])) {
      add(ingredientContexts[key], 'ingredient:$key');
    }
    final processContexts = config['process_contexts'] as Map? ?? {};
    for (final key in list(row['production_process_keys'])) {
      add(processContexts[key], 'process:$key');
    }
    final aromaContexts = config['aroma_contexts'] as Map? ?? {};
    for (final key
        in aromas.map(engine.representativeFor).whereType<String>()) {
      add(aromaContexts[key], 'aroma:$key');
    }
    // An explicit flavor word in a flavored product's name can rank suggestions;
    // it cannot change the style, ingredient list or product's aroma tags.
    final name = '${row['name'] ?? ''} ${row['name_en'] ?? ''}'.toLowerCase();
    for (final raw in config['name_contexts'] as List? ?? []) {
      final rule = raw as Map;
      final styleMatches =
          styles.any(list(rule['styles']).contains) ||
          (styles.isEmpty &&
              list(rule['unclassified_categories']).contains(category));
      if (!list(rule['categories']).contains(category) || !styleMatches) {
        continue;
      }
      // Reviewed product identities are not generic flavor words. In
      // particular, HIDAMA must not also match HIDAMA GREEN's different recipe.
      if (rule['review_basis'] != null) {
        String normalize(String value) =>
            value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
        final names = {
          normalize(row['name'] as String? ?? ''),
          normalize(row['name_en'] as String? ?? ''),
        }..remove('');
        for (final word in list(rule['words'])) {
          if (names.contains(normalize(word))) {
            add(rule['context'], 'reviewed_product:$word');
          }
        }
        continue;
      }
      for (final word in list(rule['words'])) {
        if (RegExp(
          r'(^|[\s(&+\-])' +
              RegExp.escape(word.toLowerCase()) +
              r'(?=[\s)&+\-]|와인|리큐르|리큐어|소주|막걸리|맥주|비터|하이볼|주|술|향|맛|$)',
        ).hasMatch(name)) {
          add(rule['context'], 'product_name:$word');
        }
      }
    }
    return AromaCatalogInput(
      product: AromaProductContext(
        categoryKey: category,
        assignmentTarget: AssignmentTarget.values.byName(
          row['target'] as String? ?? 'product',
        ),
        styleKeys: styles,
        sourceStyleKeys: list(row['source_styles']),
        ingredientKeys: list(row['ingredient_keys']),
        processKeys: list(row['production_process_keys']),
        aromaKeys: aromas,
        contextKeys: contextSources.keys,
      ),
      contextSources: Map.unmodifiable(contextSources),
    );
  }
}
