/// How a catalog product compares with the reader's saved cards.
enum TasteFitBadge {
  star,
  neutral,

  /// Far from what the reader liked, on no side they called a burden.
  unfamiliar,
  caution,
  noInfo;

  /// The server's name for the badge.
  String get wire => switch (this) {
    star => 'star',
    neutral => 'neutral',
    unfamiliar => 'unfamiliar',
    caution => 'caution',
    noInfo => 'no_info',
  };

  static TasteFitBadge fromWire(Object? value) => switch (value) {
    'star' => star,
    'neutral' => neutral,
    'unfamiliar' => unfamiliar,
    'caution' => caution,
    _ => noInfo,
  };
}

/// One of the bottle's own facts: producer, grape, region or process, with
/// the dictionary's short explanation when it has one.
class TasteFitFact {
  const TasteFitFact({
    required this.kind,
    required this.label,
    this.description,
  });

  final String kind;
  final String label;
  final String? description;

  static TasteFitFact? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    final label = json['label'];
    if (kind is! String || label is! String || label.isEmpty) return null;
    final description = json['description'];
    return TasteFitFact(
      kind: kind,
      label: label,
      description: description is String && description.isNotEmpty
          ? description
          : null,
    );
  }
}

/// The `taste-fit` verdict for one product, as the function returns it.
class TasteFitVerdict {
  const TasteFitVerdict({
    required this.productId,
    required this.badge,
    required this.headline,
    this.tags = const <String>[],
    this.sentence = '',
    this.levels = const <String, int>{},
    this.facts = const <TasteFitFact>[],
  });

  final String productId;
  final TasteFitBadge badge;
  final String headline;
  final List<String> tags;
  final String sentence;

  /// Product levels 1–5 by key (sweetness, acidity, …); only present keys.
  final Map<String, int> levels;

  /// Producer, grape, region and process, in display order.
  final List<TasteFitFact> facts;

  static TasteFitVerdict? fromJson(Object? json) {
    if (json is! Map) return null;
    final productId = json['product_id'];
    if (productId is! String || productId.isEmpty) return null;
    final tags = json['tags'];
    final levels = json['levels'];
    final facts = json['facts'];
    return TasteFitVerdict(
      productId: productId,
      badge: TasteFitBadge.fromWire(json['badge']),
      headline: json['headline'] is String ? json['headline'] as String : '',
      tags: tags is List
          ? List<String>.unmodifiable(tags.whereType<String>())
          : const <String>[],
      sentence: json['sentence'] is String ? json['sentence'] as String : '',
      levels: levels is Map
          ? Map<String, int>.unmodifiable(<String, int>{
              for (final entry in levels.entries)
                if (entry.key is String && entry.value is num)
                  entry.key as String: (entry.value as num).toInt(),
            })
          : const <String, int>{},
      facts: facts is List
          ? List<TasteFitFact>.unmodifiable(
              facts.map(TasteFitFact.fromJson).nonNulls,
            )
          : const <TasteFitFact>[],
    );
  }
}

/// One `taste-fit` answer: whether the reader has cards at all, and the
/// verdict of every product that was asked about.
class TasteFitResponse {
  const TasteFitResponse({required this.hasCards, required this.verdicts});

  final bool hasCards;
  final Map<String, TasteFitVerdict> verdicts;

  TasteFitVerdict? verdictFor(String productId) => verdicts[productId];

  static TasteFitResponse fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('taste-fit response is not an object');
    }
    final products = json['products'];
    return TasteFitResponse(
      hasCards: json['has_cards'] == true,
      verdicts:
          Map<String, TasteFitVerdict>.unmodifiable(<String, TasteFitVerdict>{
            if (products is List)
              for (final verdict
                  in products.map(TasteFitVerdict.fromJson).nonNulls)
                verdict.productId: verdict,
          }),
    );
  }
}
