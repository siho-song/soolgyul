/// Local implementation of ADR-123/124. This has no network, persistence or
/// taste-card dependency. Candidates are neither product facts nor preferences.
library;

import '../../../core/catalog/catalog_assignment.dart';
import 'aroma_choice_models.dart';

export 'aroma_choice_models.dart';

part 'direct_aroma_rule.dart';

/// Reference JSON and the existing service dictionary are injected, so rules
/// can be replaced independently of the question screen or interpretation engine.
class DirectAromaChoiceEngine {
  DirectAromaChoiceEngine({
    required Map<String, dynamic> reference,
    required Map<String, dynamic> vocabulary,
    required Map<String, dynamic> sourceCatalog,
    required Map<String, dynamic> alcoholTaxonomy,
  }) : ruleVersion = reference['version'] as String {
    if (![1, 2].contains(reference['schema_version']) ||
        reference['vocabulary_version'] != vocabulary['schema_version'] ||
        reference['taxonomy_version'] != vocabulary['taxonomy_version']) {
      throw FormatException('Unsupported aroma reference/vocabulary version');
    }
    _readTerms(vocabulary, sourceCatalog);
    _readFamiliarity(reference);
    final sourceIds = (reference['sources'] as Map).keys.toSet();
    final categories = (alcoholTaxonomy['categories'] as List)
        .map((row) => row['category_key'] as String)
        .toSet();
    _readStyles(alcoholTaxonomy);
    // Rule facets are production facts: process and maturation term keys.
    final production = alcoholTaxonomy['production'] as Map;
    final facets = <String>{
      for (final term in [
        ...production['process_terms'] as List,
        ...production['maturation_terms'] as List,
      ])
        term['term_key'] as String,
    };
    _readCategoryScope(reference, categories);
    final candidateGroups = _readCandidateGroups(reference);
    _readCatalogContext(reference, categories);
    _candidateGroups.addAll(candidateGroups.values);
    for (final row in reference['rules'] as List) {
      final rule = _AromaRule(
        Map<String, dynamic>.from(row as Map),
        candidateGroups,
      );
      if (!_isValidRule(rule, sourceIds, categories, facets)) {
        throw FormatException('Invalid aroma rule: ${rule.id}');
      }
      _rules.add(rule);
    }
  }

  /// Aroma representatives from the vocabulary, with every source key and
  /// label that searches or catalog tags may use for them.
  void _readTerms(
    Map<String, dynamic> vocabulary,
    Map<String, dynamic> sourceCatalog,
  ) {
    final sources = <String, Map<String, dynamic>>{
      for (final section in ['descriptors', 'textures', 'finish_characters'])
        for (final row in sourceCatalog[section] as List)
          row['key'] as String: Map<String, dynamic>.from(row as Map),
    };
    final groups = (vocabulary['groups'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    for (final group in groups) {
      final key = group['key'] as String;
      if (group['domain'] != 'descriptor' ||
          !_strings(group['phases']).contains('aroma')) {
        continue;
      }
      if (_terms.containsKey(key)) {
        throw FormatException('Duplicate aroma representative: $key');
      }
      final search = <String>{key, group['label_ko'] as String};
      search.addAll(_strings(group['user_source_labels']));
      for (final rawKey in _strings(group['source_keys'])) {
        final source = sources[rawKey];
        if (source == null) throw FormatException('Unknown source: $rawKey');
        // Keep the source phase restriction before collapsing representatives.
        if (_strings(source['phases']).contains('aroma')) {
          _targets[rawKey] = key;
          search.addAll([rawKey, source['label_ko'] as String]);
          if (source['label_en'] is String) {
            search.add(source['label_en'] as String);
          }
        }
      }
      _targets[key] = key;
      _families[key] = group['category_key'] as String;
      _terms[key] = _AromaTerm(
        key,
        group['label_ko'] as String,
        search.map(_searchText).toSet(),
      );
    }
    for (final entry in (vocabulary['legacy_aliases'] as Map).entries) {
      final target = _targets[entry.value];
      if (target != null) _targets[entry.key as String] = target;
    }
    _knownKeys.addAll(sources.keys);
    _knownKeys.addAll(_targets.keys);
    _knownKeys.addAll(
      (vocabulary['legacy_aliases'] as Map).keys.cast<String>(),
    );
    _knownKeys.addAll(
      (vocabulary['pending'] as List).map((row) => row['key'] as String),
    );
  }

  void _readFamiliarity(Map<String, dynamic> reference) {
    for (final key in _strings(reference['less_familiar_keys'])) {
      if (!_terms.containsKey(key)) throw FormatException('Unknown key: $key');
      _lessFamiliar.add(key);
    }
    // Overlap groups only relate aromas when filling the list; never merged.
    for (final group in reference['extension_overlap_groups'] as List) {
      final keys = _strings(group);
      for (final key in keys) {
        if (!_terms.containsKey(key) || _overlapGroups.containsKey(key)) {
          throw FormatException('Invalid extension group: $key');
        }
        _overlapGroups[key] = keys.first;
      }
    }
  }

  void _readStyles(Map<String, dynamic> alcoholTaxonomy) {
    final styles = {
      for (final row in alcoholTaxonomy['primary_styles'] as List)
        row['style_key'] as String: row['category_key'] as String,
    };
    _styleCategories.addAll(styles);
    _styleRedirects.addAll(
      Map<String, String>.from(
        alcoholTaxonomy['style_redirects'] as Map? ?? {},
      ),
    );
    for (final entry in _styleRedirects.entries) {
      if (styles.containsKey(entry.key) || !styles.containsKey(entry.value)) {
        throw FormatException('Invalid style redirect: ${entry.key}');
      }
      _styleCategories[entry.key] = styles[entry.value]!;
    }
  }

  void _readCategoryScope(
    Map<String, dynamic> reference,
    Set<String> categories,
  ) {
    final documentedCategories = (reference['category_limits'] as Map).keys
        .toSet();
    if (!categories.containsAll(documentedCategories) ||
        !documentedCategories.containsAll(categories)) {
      throw FormatException('Every alcohol category needs a reference scope');
    }
    for (final entry in (reference['category_fallback'] as Map).entries) {
      final keys = _strings(entry.value);
      if (!categories.contains(entry.key) ||
          keys.any((key) => !_terms.containsKey(key))) {
        throw FormatException('Invalid category fallback: ${entry.key}');
      }
      _categoryFallback[entry.key as String] = keys;
    }
  }

  Map<String, Map<String, int>> _readCandidateGroups(
    Map<String, dynamic> reference,
  ) {
    final candidateGroups = <String, Map<String, int>>{
      for (final entry in (reference['candidate_groups'] as Map? ?? {}).entries)
        entry.key as String: Map<String, int>.from(entry.value as Map),
    };
    for (final group in candidateGroups.entries) {
      if (group.key.isEmpty ||
          group.value.isEmpty ||
          group.value.entries.any(
            (entry) =>
                !_terms.containsKey(entry.key) ||
                entry.value < 40 ||
                entry.value > 90,
          )) {
        throw FormatException('Invalid candidate group: ${group.key}');
      }
    }
    return candidateGroups;
  }

  void _readCatalogContext(
    Map<String, dynamic> reference,
    Set<String> categories,
  ) {
    _contextKeys.addAll(
      (reference['contexts'] as Map? ?? {}).keys.cast<String>(),
    );
    final catalogContext = reference['catalog_context'] as Map? ?? {};
    _aromaContexts.addAll(
      Map<String, String>.from(catalogContext['aroma_contexts'] as Map? ?? {}),
    );
    _processContexts.addAll(
      Map<String, String>.from(
        catalogContext['process_contexts'] as Map? ?? {},
      ),
    );
    if (_processContexts.keys.any(
      (key) => CatalogProcessKey.fromKey(key) == null,
    )) {
      throw FormatException('Unknown process in process_contexts');
    }
    for (final field in [
      'ingredient_contexts',
      'aroma_contexts',
      'process_contexts',
    ]) {
      if ((catalogContext[field] as Map? ?? {}).values.any(
        (value) => value is! String || !_contextKeys.contains(value),
      )) {
        throw FormatException('Unknown catalog context in $field');
      }
    }
    for (final raw in catalogContext['name_contexts'] as List? ?? []) {
      final rule = raw as Map;
      final scope = _strings(rule['categories']);
      if (!_contextKeys.contains(rule['context']) ||
          _strings(rule['words']).isEmpty ||
          _strings(rule['words']).any((s) => s.trim().isEmpty) ||
          scope.isEmpty ||
          !categories.containsAll(scope) ||
          !_strings(rule['unclassified_categories']).every(scope.contains) ||
          _strings(
            rule['styles'],
          ).any((s) => !scope.contains(_styleCategories[s]))) {
        throw FormatException(
          'Invalid catalog name context: ${rule['context']}',
        );
      }
    }
  }

  bool _isValidRule(
    _AromaRule rule,
    Set<Object?> sourceIds,
    Set<String> categories,
    Set<String> facets,
  ) {
    final ruleCategories = _strings(rule.when['categories']);
    return !_rules.any((other) => other.id == rule.id) &&
        rule.reason.trim().isNotEmpty &&
        rule.sourceIds.isNotEmpty &&
        sourceIds.containsAll(rule.sourceIds) &&
        ruleCategories.isNotEmpty &&
        categories.containsAll(ruleCategories) &&
        ![
          ..._strings(rule.when['styles_any']),
          ..._strings(rule.when['styles_none']),
        ].any((key) => !ruleCategories.contains(_styleCategories[key])) &&
        facets.containsAll(_strings(rule.when['facets_any'])) &&
        rule.when.keys.every(_ruleConditionKeys.contains) &&
        _contextKeys.containsAll([
          ..._strings(rule.when['contexts_any']),
          ..._strings(rule.when['contexts_none']),
        ]) &&
        rule.candidates.isNotEmpty &&
        !rule.candidates.entries.any(
          (entry) =>
              !_terms.containsKey(entry.key) ||
              entry.value < 40 ||
              entry.value > 90,
        ) &&
        [
          ..._strings(rule.when['aromas_any']),
          ..._strings(rule.when['aromas_none']),
        ].every(_terms.containsKey);
  }

  static const _ruleConditionKeys = {
    'categories',
    'styles_any',
    'styles_none',
    'facets_any',
    'aromas_any',
    'aromas_none',
    'contexts_any',
    'contexts_none',
  };

  final String ruleVersion;
  final _terms = <String, _AromaTerm>{};
  final _targets = <String, String>{};
  final _knownKeys = <String>{};
  final _lessFamiliar = <String>{};
  final _categoryFallback = <String, List<String>>{};
  final _overlapGroups = <String, String>{};
  final _families = <String, String>{};
  final _candidateGroups = <Map<String, int>>[];
  final _rules = <_AromaRule>[];
  final _assignments = CatalogAssignmentRegistry();
  final _styleCategories = <String, String>{};
  final _styleRedirects = <String, String>{};
  final _contextKeys = <String>{};
  final _aromaContexts = <String, String>{};
  final _processContexts = <String, String>{};

  int get searchableCount => _terms.length;
  Set<String> get selectableKeys => Set.unmodifiable(_terms.keys);

  String? representativeFor(String sourceKey) => _targets[sourceKey];

  DirectAromaResolution resolve(AromaProductContext product) {
    final currentStyles = product.styleKeys
        .map((key) => _styleRedirects[key] ?? key)
        .toSet();
    // A key this app cannot place is dropped and the product is asked about
    // with what is known; only an unknown category stops it.
    final validation = _assignments.validateKnown({
      'category_key': product.categoryKey,
      'style_key': currentStyles.length == 1 ? currentStyles.single : null,
      'target': product.assignmentTarget.name,
      'ingredient_keys': product.ingredientKeys.toList(),
      'production_process_keys': product.processKeys.toList(),
    });
    final assignment = validation.value;
    if (assignment == null) {
      return DirectAromaResolution(
        ruleVersion: ruleVersion,
        status: AromaChoiceStatus.invalidInput,
        options: const [],
        productKeys: const [],
        warnings: validation.issues.map(
          (issue) => 'invalid_catalog_assignment:${issue.identity}',
        ),
      );
    }
    final styleKey = assignment.styleKey?.key;
    final matchingStyles = <String>{?styleKey};
    for (final key in {...product.styleKeys, ...product.sourceStyleKeys}) {
      // Never expand a broad style to all children. A preserved child must
      // redirect to this product's actual current style in the same category.
      if (_styleCategories[key] == product.categoryKey &&
          styleKey == (_styleRedirects[key] ?? key)) {
        matchingStyles.add(key);
      }
    }
    final productKeys = product.aromaKeys
        .map((key) => _targets[key])
        .whereType<String>()
        .toSet();
    final matchingProduct = AromaProductContext(
      categoryKey: assignment.categoryKey.key,
      styleKeys: matchingStyles,
      processKeys: assignment.processKeys.map((key) => key.key),
      aromaKeys: product.aromaKeys,
      contextKeys: {
        ...product.contextKeys.where(_contextKeys.contains),
        ...productKeys.map((key) => _aromaContexts[key]).whereType<String>(),
        ...assignment.processKeys
            .map((key) => _processContexts[key.key])
            .whereType<String>(),
      },
    );
    // An aroma this app does not know only goes unranked.
    final warnings = <String>[
      if (currentStyles.length > 1)
        'dropped_catalog_key:multiple_primary_styles',
      ...validation.issues.map(
        (issue) => 'dropped_catalog_key:${issue.identity}',
      ),
      for (final key in product.aromaKeys.toList()..sort())
        if (!_knownKeys.contains(key)) 'unknown_aroma_key:$key',
    ];
    final scores = <String, int>{};
    final reasons = <String, Set<String>>{};
    for (final rule in _rules) {
      if (!rule.matches(matchingProduct, productKeys)) continue;
      for (final entry in rule.candidates.entries) {
        if (entry.value > (scores[entry.key] ?? 0)) {
          scores[entry.key] = entry.value;
        }
        reasons.putIfAbsent(entry.key, () => {}).add(rule.id);
      }
    }
    // Product tags outrank supplements. Tag order/count and duplicate profiles
    // have no effect. Style support only breaks ties among product-listed tags.
    for (final key in productKeys) {
      scores[key] = 100 + (scores[key] ?? 0) ~/ 10;
    }
    final ranked = scores.keys.toList()
      ..sort((a, b) {
        final scoreOrder = scores[b]!.compareTo(scores[a]!);
        if (scoreOrder != 0) return scoreOrder;
        final familiarityOrder = (_lessFamiliar.contains(a) ? 1 : 0).compareTo(
          _lessFamiliar.contains(b) ? 1 : 0,
        );
        return familiarityOrder != 0 ? familiarityOrder : a.compareTo(b);
      });
    final ordered = _fillRelated(ranked, product.categoryKey);
    if (productKeys.difference(ordered.toSet()).isNotEmpty) {
      warnings.add('some_product_aromas_search_only');
    }
    return _resolution(
      ordered,
      scores,
      reasons,
      productKeys,
      warnings,
      styleKey,
    );
  }

  static const _pageSize = 10;

  DirectAromaResolution _resolution(
    List<String> ordered,
    Map<String, int> scores,
    Map<String, Set<String>> reasons,
    Set<String> productKeys,
    Iterable<String> warnings,
    String? styleKey,
  ) {
    DirectAromaOption option(String key) => DirectAromaOption(
      key: key,
      label: _terms[key]!.label,
      score: scores[key] ?? 0,
      productListed: productKeys.contains(key),
      ruleIds: (reasons[key] ?? <String>{}).toList()..sort(),
    );
    return DirectAromaResolution(
      ruleVersion: ruleVersion,
      status: AromaChoiceStatus.ready,
      styleKey: styleKey,
      productKeys: productKeys,
      warnings: warnings,
      options: ordered.take(_pageSize).map(option),
      moreOptions: ordered.skip(_pageSize).map(option),
    );
  }

  /// Ranked keys first, then aromas related to already listed ones (same
  /// overlap group, candidate group, or vocabulary family), then the drink
  /// category's typical aromas, then familiar aromas in vocabulary order, up
  /// to two pages.
  List<String> _fillRelated(List<String> ranked, String? categoryKey) {
    const limit = _pageSize * 2;
    final ordered = ranked.take(limit).toList();
    final listed = ordered.toSet();
    void add(String key) {
      if (ordered.length < limit && listed.add(key)) ordered.add(key);
    }

    for (var i = 0; i < ordered.length && ordered.length < limit; i++) {
      _related(ordered[i]).forEach(add);
    }
    _categoryFallback[categoryKey]?.forEach(add);
    _terms.keys.where((key) => !_lessFamiliar.contains(key)).forEach(add);
    return ordered;
  }

  /// Familiar keys come before less familiar ones within each relation.
  List<String> _related(String key) {
    final overlap = _overlapGroups[key];
    final family = _families[key];
    final related = [
      if (overlap != null)
        ..._overlapGroups.keys.where((k) => _overlapGroups[k] == overlap),
      for (final group in _candidateGroups.where((g) => g.containsKey(key)))
        ...(group.keys.toList()
          ..sort((a, b) => group[b]!.compareTo(group[a]!))),
      ..._terms.keys.where((k) => _families[k] == family),
    ];
    return [
      ...related.where((k) => !_lessFamiliar.contains(k)),
      ...related.where(_lessFamiliar.contains),
    ];
  }

  /// Searches the whole visible aroma dictionary, never a product's shortlist.
  /// Only returned canonical keys can be selected; query text is not an answer.
  List<DirectAromaOption> search(String query) {
    final needle = _searchText(query.trim());
    if (needle.isEmpty) return const [];
    final matches =
        _terms.values
            .where(
              (term) => term.searchTerms.any((text) => text.contains(needle)),
            )
            .toList()
          ..sort((a, b) {
            final exact = (b.searchTerms.contains(needle) ? 1 : 0).compareTo(
              a.searchTerms.contains(needle) ? 1 : 0,
            );
            return exact != 0 ? exact : a.key.compareTo(b.key);
          });
    return List.unmodifiable(
      matches.map(
        (term) => DirectAromaOption(
          key: term.key,
          label: term.label,
          score: 0,
          productListed: false,
          ruleIds: const [],
        ),
      ),
    );
  }
}
