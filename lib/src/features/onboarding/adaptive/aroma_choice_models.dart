import '../../../core/catalog/catalog_assignment.dart';

class AromaProductContext {
  AromaProductContext({
    required this.categoryKey,
    this.assignmentTarget = AssignmentTarget.product,
    Iterable<String> styleKeys = const [],
    Iterable<String> sourceStyleKeys = const [],
    Iterable<String> ingredientKeys = const [],
    Iterable<String> processKeys = const [],
    Iterable<String> aromaKeys = const [],
    Iterable<String> contextKeys = const [],
  }) : styleKeys = Set.unmodifiable(styleKeys),
       sourceStyleKeys = Set.unmodifiable(sourceStyleKeys),
       ingredientKeys = Set.unmodifiable(ingredientKeys),
       processKeys = Set.unmodifiable(processKeys),
       aromaKeys = Set.unmodifiable(aromaKeys),
       contextKeys = Set.unmodifiable(contextKeys);

  final String categoryKey;
  final AssignmentTarget assignmentTarget;
  final Set<String> styleKeys;
  // Preserved source classifications, not user answers or inferred children.
  final Set<String> sourceStyleKeys;
  final Set<String> ingredientKeys;
  final Set<String> processKeys;
  // Aroma-phase tags only. Do not pass flavor/palate/finish/ingredient fields.
  final Set<String> aromaKeys;
  // Catalog cues for selecting suggestions, NEVER product aromas or answers.
  final Set<String> contextKeys;
}

class DirectAromaOption {
  DirectAromaOption({
    required this.key,
    required this.label,
    required this.score,
    required this.productListed,
    required Iterable<String> ruleIds,
  }) : ruleIds = List.unmodifiable(ruleIds);

  final String key;
  final String label;
  // Ranking points, NOT sensory intensity or a probability.
  final int score;
  final bool productListed;
  final List<String> ruleIds;
}

enum AromaChoiceStatus { ready, invalidInput }

class DirectAromaResolution {
  DirectAromaResolution({
    required this.ruleVersion,
    required Iterable<DirectAromaOption> options,
    required Iterable<String> productKeys,
    required Iterable<String> warnings,
    required this.status,
    this.styleKey,
    Iterable<DirectAromaOption> moreOptions = const [],
  }) : options = List.unmodifiable(options),
       moreOptions = List.unmodifiable(moreOptions),
       productKeys = Set.unmodifiable(productKeys.toList()..sort()),
       warnings = List.unmodifiable(warnings);

  final String ruleVersion;
  // First page shown by default; [moreOptions] is revealed by "향 더 보기".
  final List<DirectAromaOption> options;
  final List<DirectAromaOption> moreOptions;
  final Set<String> productKeys;
  final List<String> warnings;
  final AromaChoiceStatus status;

  /// The product's primary style as this app reads it: redirected to its
  /// current key, or null when it has none this app can place.
  final String? styleKey;
}
