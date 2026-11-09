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

/// Local catalog adapter. Never reads a user's memo or writes catalog facts.
class AromaCatalogInput {
  AromaCatalogInput({
    required this.product,
    required this.recoveredAromaKeys,
    required this.contextSources,
  });

  final AromaProductContext product;
  final Set<String> recoveredAromaKeys;
  final Map<String, Set<String>> contextSources;
}

class AromaCatalogInputAdapter {
  AromaCatalogInputAdapter({
    required this.engine,
    required Map<String, dynamic> reference,
    required Map<String, dynamic> vocabulary,
    required Map<String, dynamic> sourceCatalog,
  }) : config =
           _freezeConfig(reference['catalog_context'] ?? {})
               as Map<String, dynamic> {
    final sources = <String, Map>{
      for (final row in sourceCatalog['descriptors'] as List)
        row['key'] as String: row as Map,
    };
    for (final group in vocabulary['groups'] as List) {
      final key = group['key'] as String;
      if (!engine.selectableKeys.contains(key)) continue;
      void alias(Object? value) {
        if (value is! String) return;
        final label = value.toLowerCase().trim().replaceFirst(
          RegExp(r'\s*향$'),
          '',
        );
        if (label.isNotEmpty) {
          _aliases.putIfAbsent(label, () => <String>{}).add(key);
        }
      }

      alias(group['label_ko']);
      for (final rawKey in group['source_keys'] as List) {
        if (engine.representativeFor(rawKey as String) != key) continue;
        final source = sources[rawKey];
        if (source == null) continue;
        alias(source['label_ko']);
        alias(source['label_en']);
        for (final v in source['aliases'] as List? ?? []) {
          alias(v);
        }
      }
    }
    // Ambiguous surface forms do not become several product facts.
    _aliases.removeWhere((_, keys) => keys.length != 1);
  }

  final DirectAromaChoiceEngine engine;
  final Map<String, dynamic> config;
  final _aliases = <String, Set<String>>{};

  Set<String> _readAromaNote(String text) {
    final found = <String>{};
    // A negation may govern a preceding comma-separated list too.
    if (RegExp(
      r'없|않|아니|아닌|제외|무향|\b(no|not|without|free)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return found;
    }
    final labels = _aliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    // Prefer leaving prose unresolved to confusing absence, tasting/pairing or
    // ingredients with a positive nose descriptor. Structured lists work too.
    for (final clause in text.toLowerCase().split(RegExp(r'[,;\n.!?]'))) {
      if (RegExp(
        r'없|않|아니|아닌|제외|무향|원료|재료|첨가|칵테일|페어링|맛|마무리|여운|질감|\b(no|not|without|free|palate|finish|cocktail|pairing)\b',
      ).hasMatch(clause)) {
        continue;
      }
      var remaining = clause;
      for (final label in labels) {
        final pattern = RegExp('(?<![a-z])${RegExp.escape(label)}(?![a-z])');
        for (final match in pattern.allMatches(remaining).toList().reversed) {
          // Longer aliases may already have blanked "melon" in remaining.
          // Check the original clause at the same offset before accepting musk.
          if (_aliases[label]!.single == 'musk' &&
              RegExp(
                r'^[\s(（-]*(?:melon|멜론|메론)',
              ).hasMatch(clause.substring(match.end))) {
            continue;
          }
          if (label.length == 1 &&
              ((match.start > 0 &&
                      RegExp(r'[가-힣]').hasMatch(remaining[match.start - 1])) ||
                  (match.end < remaining.length &&
                      !RegExp(
                        r'[\s·:/()향의]',
                      ).hasMatch(remaining[match.end])))) {
            continue;
          }
          found.add(_aliases[label]!.single);
          remaining = remaining.replaceRange(
            match.start,
            match.end,
            ' ' * (match.end - match.start),
          );
        }
      }
    }
    return found;
  }

  AromaCatalogInput read(Map<String, dynamic> row) {
    List<String> list(Object? value) => List<String>.from(value as List? ?? []);
    final category = row['category'] as String;
    final styles = row['styles'] != null
        ? list(row['styles'])
        : [if (row['style_key'] is String) row['style_key'] as String];
    final aromas = list(row['aroma_keys']).toSet();
    final recovered = <String>{};
    if (config['recover_source_aroma_notes'] == true) {
      for (final raw in row['aroma_notes'] as List? ?? []) {
        final note = raw as Map;
        final uri = Uri.tryParse(note['source_url'] as String? ?? '');
        if (note['origin'] != 'verified' ||
            note['publish_status'] == 'withdrawn' ||
            note['review_status'] == 'rejected' ||
            note['alcohol_release_id'] != null ||
            uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty) {
          continue;
        }
        recovered.addAll(_readAromaNote(note['note'] as String? ?? ''));
      }
    }
    final existing = aromas
        .map(engine.representativeFor)
        .whereType<String>()
        .toSet();
    recovered.removeAll(existing);
    aromas.addAll(recovered);
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
      recoveredAromaKeys: Set.unmodifiable(recovered),
      contextSources: Map.unmodifiable(contextSources),
    );
  }
}
