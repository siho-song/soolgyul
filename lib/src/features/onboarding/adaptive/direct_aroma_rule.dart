part of 'direct_aroma_choices.dart';

class _AromaTerm {
  const _AromaTerm(this.key, this.label, this.searchTerms);
  final String key;
  final String label;
  final Set<String> searchTerms;
}

List<String> _strings(Object? value) =>
    value == null ? const [] : List<String>.from(value as List);

String _searchText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_·()\-]'), '')
    .replaceFirst(RegExp(r'향$'), '');

class _AromaRule {
  _AromaRule(Map<String, dynamic> json, Map<String, Map<String, int>> groups)
    : id = json['id'] as String,
      when = _conditions(json['when'] as Map),
      candidates = _candidates(json, groups),
      reason = json['reason_ko'] as String,
      sourceIds = _strings(json['source_ids']);

  final String id;
  final Map<String, dynamic> when;
  final Map<String, int> candidates;
  final String reason;
  final List<String> sourceIds;

  static Map<String, int> _candidates(
    Map<String, dynamic> json,
    Map<String, Map<String, int>> groups,
  ) {
    final result = <String, int>{};
    for (final key in _strings(json['candidate_groups'])) {
      final group = groups[key];
      if (group == null) throw FormatException('Unknown candidate group: $key');
      for (final entry in group.entries) {
        if (entry.value > (result[entry.key] ?? 0)) {
          result[entry.key] = entry.value;
        }
      }
    }
    result.addAll(Map<String, int>.from(json['candidates'] as Map? ?? {}));
    return Map.unmodifiable(result);
  }

  static Map<String, dynamic> _conditions(Map input) {
    final result = <String, dynamic>{};
    for (final entry in input.entries) {
      if (entry.key is! String ||
          entry.value is! List ||
          (entry.value as List).isEmpty ||
          (entry.value as List).any(
            (value) => value is! String || value.isEmpty,
          )) {
        throw FormatException('Rule conditions must be nonempty string lists');
      }
      result[entry.key as String] = List<String>.unmodifiable(
        _strings(entry.value),
      );
    }
    return Map.unmodifiable(result);
  }

  bool matches(AromaProductContext product, Set<String> aromas) {
    bool intersects(String key, Set<String> values) =>
        _strings(when[key]).any(values.contains);
    return _strings(when['categories']).contains(product.categoryKey) &&
        (_strings(when['styles_any']).isEmpty ||
            intersects('styles_any', product.styleKeys)) &&
        !intersects('styles_none', product.styleKeys) &&
        (_strings(when['facets_any']).isEmpty ||
            intersects('facets_any', product.processKeys)) &&
        (_strings(when['aromas_any']).isEmpty ||
            intersects('aromas_any', aromas)) &&
        !intersects('aromas_none', aromas) &&
        (_strings(when['contexts_any']).isEmpty ||
            intersects('contexts_any', product.contextKeys)) &&
        !intersects('contexts_none', product.contextKeys);
  }
}
