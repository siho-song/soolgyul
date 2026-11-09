import 'assignment_contract.g.dart';
export 'assignment_contract.g.dart'
    show
        CatalogCategoryKey,
        CatalogStyleKey,
        CatalogIngredientKey,
        CatalogProcessKey;

enum AssignmentTarget { product, release }

enum CatalogTermKind { style, ingredient, process, maturation }

class AssignmentIssue {
  const AssignmentIssue(this.code, this.field, [this.key = '']);
  final String code;
  final String field;
  final String key;
  String get identity => '$code:$field:$key';
  Map<String, String> toJson() => {'code': code, 'field': field, 'key': key};
}

/// Private constructor: only the registry may create this immutable value.
class CatalogAssignment {
  CatalogAssignment._(
    this.categoryKey,
    this.styleKey,
    this.target,
    Map<String, List<String>> values,
  ) : ingredientKeys = List.unmodifiable(
        values['ingredient_keys']!.map((k) => CatalogIngredientKey.fromKey(k)!),
      ),
      processKeys = List.unmodifiable(
        values['production_process_keys']!.map(
          (k) => CatalogProcessKey.fromKey(k)!,
        ),
      );
  final CatalogCategoryKey categoryKey;
  final CatalogStyleKey? styleKey;
  final AssignmentTarget target;
  final List<CatalogIngredientKey> ingredientKeys;
  final List<CatalogProcessKey> processKeys;
  // String keys exist only at serialization/legacy consumer boundaries.
  Map<String, List<String>> get values => Map.unmodifiable({
    'ingredient_keys': List<String>.unmodifiable(
      ingredientKeys.map((v) => v.key),
    ),
    'production_process_keys': List<String>.unmodifiable(
      processKeys.map((v) => v.key),
    ),
  });
  Map<String, Object?> toJson() => {
    'category_key': categoryKey.key,
    'style_key': styleKey?.key,
    'target': target.name,
    ...values,
  };
}

class AssignmentValidation {
  AssignmentValidation(this.value, Iterable<AssignmentIssue> issues)
    : issues = List.unmodifiable(issues);
  final CatalogAssignment? value;
  final List<AssignmentIssue> issues;
  CatalogAssignment requireValid() {
    if (value == null) {
      throw FormatException(issues.map((i) => i.identity).join('; '));
    }
    return value!;
  }
}

class _Rule {
  _Rule(Map<String, dynamic> row)
    : kind = CatalogTermKind.values.byName(row['kind'] as String),
      key = row['key'] as String,
      categories = Set.unmodifiable(
        List<String>.from(row['categories'] as List),
      ),
      styles = Set.unmodifiable(List<String>.from(row['styles'] as List)),
      target = row['target'] as String,
      excludes = Set.unmodifiable(List<String>.from(row['excludes'] as List));
  final CatalogTermKind kind;
  final String key;
  final Set<String> categories;
  final Set<String> styles;
  final String target;
  final Set<String> excludes;
}

class CatalogAssignmentRegistry {
  CatalogAssignmentRegistry([
    Map<String, dynamic> source = catalogAssignmentContract,
  ]) {
    if (source['schema_version'] != 2) {
      throw const FormatException('Unsupported assignment contract');
    }
    _categories.addAll(List<String>.from(source['categories'] as List));
    if (_categories.any((key) => CatalogCategoryKey.fromKey(key) == null)) {
      throw const FormatException(
        'Category enum/contract mismatch; regenerate',
      );
    }
    for (final row in source['terms'] as List) {
      final rule = _Rule(Map<String, dynamic>.from(row as Map));
      final id = '${rule.kind.name}:${rule.key}';
      final knownKey = switch (rule.kind) {
        CatalogTermKind.style => CatalogStyleKey.fromKey(rule.key) != null,
        CatalogTermKind.ingredient =>
          CatalogIngredientKey.fromKey(rule.key) != null,
        CatalogTermKind.process || CatalogTermKind.maturation =>
          CatalogProcessKey.fromKey(rule.key) != null,
      };
      if (!knownKey ||
          _rules.containsKey(id) ||
          !['product', 'release', 'both'].contains(rule.target) ||
          rule.categories.isEmpty ||
          !rule.categories.every(_categories.contains)) {
        throw FormatException('Invalid assignment rule: $id');
      }
      _rules[id] = rule;
    }
  }
  final _categories = <String>{};
  final _rules = <String, _Rule>{};
  static const _kinds = {
    'ingredient_keys': ['ingredient'],
    'production_process_keys': ['process', 'maturation'],
  };

  AssignmentValidation validate(Map<String, Object?> raw) {
    final issues = <AssignmentIssue>[];
    void issue(String code, String field, [String key = '']) =>
        issues.add(AssignmentIssue(code, field, key));
    final category = raw['category_key'];
    final style = raw['style_key'];
    final rawTarget = raw.containsKey('target') ? raw['target'] : 'product';
    final target = rawTarget == 'release'
        ? AssignmentTarget.release
        : AssignmentTarget.product;
    if (rawTarget != 'product' && rawTarget != 'release') {
      issue('invalid_target', 'target');
    }
    if (category is! String || !_categories.contains(category)) {
      issue('unknown_category', 'category_key');
    }
    void check(_Rule rule, String field) {
      if (!rule.categories.contains(category)) {
        issue('wrong_category', field, rule.key);
      }
      if (rule.styles.isNotEmpty && !rule.styles.contains(style)) {
        issue('wrong_style', field, rule.key);
      }
      if (rule.target != 'both' && rule.target != target.name) {
        issue('wrong_target', field, rule.key);
      }
    }

    if (style != null) {
      final rule = style is String ? _rules['style:$style'] : null;
      if (rule == null) {
        issue('unknown_term', 'style_key', style is String ? style : '');
      } else {
        check(rule, 'style_key');
      }
    }
    final arrays = <String, List<String>>{};
    for (final entry in _kinds.entries) {
      final field = entry.key;
      final values = raw.containsKey(field) ? raw[field] : <String>[];
      arrays[field] = [];
      if (values is! List) {
        issue('invalid_array', field);
        continue;
      }
      if (values.length > 64) issue('too_many_terms', field);
      final seen = <String>{};
      final selected = <_Rule>[];
      final pattern = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final key in values) {
        if (key is! String || key.trim() != key || !pattern.hasMatch(key)) {
          issue('invalid_key', field);
          continue;
        }
        if (!seen.add(key)) issue('duplicate_term', field, key);
        final matches = entry.value
            .map((kind) => _rules['$kind:$key'])
            .whereType<_Rule>()
            .toList();
        if (matches.length != 1) {
          issue(
            matches.isEmpty ? 'unknown_term' : 'ambiguous_term',
            field,
            key,
          );
          continue;
        }
        check(matches.single, field);
        selected.add(matches.single);
      }
      arrays[field] = seen.toList()..sort();
      for (final rule in selected) {
        if (rule.excludes.any(seen.contains)) {
          issue('excluded_combination', field, rule.key);
        }
      }
    }
    final unique = {for (final i in issues) i.identity: i}.values.toList()
      ..sort((a, b) => a.identity.compareTo(b.identity));
    return AssignmentValidation(
      unique.isEmpty
          ? CatalogAssignment._(
              CatalogCategoryKey.fromKey(category as String)!,
              style == null ? null : CatalogStyleKey.fromKey(style as String)!,
              target,
              arrays,
            )
          : null,
      unique,
    );
  }
}
