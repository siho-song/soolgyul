import '../../../core/catalog/drink_type.dart';

/// The drinks a term belongs to, as 나의 용어 사전 filters by them.
enum TermDrink {
  /// A term of every drink: a scent, a taste, a texture.
  common(null),
  wine(DrinkType.wine),
  whisky(DrinkType.whisky),
  sake(DrinkType.sake),
  koreanTraditional(DrinkType.koreanTraditional);

  const TermDrink(this.type);

  /// Its 주종; null for [common].
  final DrinkType? type;

  String get wire => type?.key ?? 'common';
  String get label => type?.label ?? '공통';
}

/// One kind of drink a place makes, as the reader saved it from a balloon:
/// 산 후안 · 레드.
class SavedStyle {
  const SavedStyle({
    required this.key,
    required this.label,
    required this.description,
  });

  /// The key its balloon saves it by (regional_style:san_juan_red).
  final String key;

  /// 레드, 화이트, 스파클링.
  final String label;
  final String description;

  static SavedStyle? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final label = json['label'];
    final description = json['description'];
    if (key is! String || label is! String || description is! String) {
      return null;
    }
    return SavedStyle(key: key, label: label, description: description);
  }
}

/// A term the reader saved from its help balloon, as the dictionary explains
/// it now. A place is one term however many of its styles were saved: its
/// own explanation ([intro]) and then each saved style ([parts]).
class SavedTerm {
  const SavedTerm({
    required this.key,
    required this.label,
    required this.kind,
    required this.drinks,
    required this.description,
    this.intro,
    this.own = true,
    this.parts = const <SavedStyle>[],
  });

  /// The dictionary's key of the term (aroma:cherry).
  final String key;
  final String label;

  /// 향, 맛, 질감, 여운, 제조·숙성, 품종, 산지, 생산자.
  final String kind;

  /// Empty when the dictionary does not say which drinks the term is of.
  final Set<TermDrink> drinks;

  /// The whole explanation in one text. A place with [parts] is shown by
  /// [intro] and its parts instead.
  final String description;

  /// A place's own explanation; `null` when the dictionary has none, or for
  /// a term that is no place.
  final String? intro;

  /// Whether this term itself was saved. A place the reader saved only a
  /// style of is listed without being saved itself.
  final bool own;

  /// The styles of the place the reader saved, newest first.
  final List<SavedStyle> parts;

  /// Whether the balloon of [termKey] finds its save here.
  bool holds(String termKey) =>
      (own && key == termKey) || parts.any((part) => part.key == termKey);

  static SavedTerm? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final label = json['label'];
    final kind = json['kind'];
    final description = json['description'];
    final categories = json['categories'];
    final intro = json['intro'];
    final own = json['own'];
    final parts = json['parts'];
    if (key is! String ||
        label is! String ||
        kind is! String ||
        description is! String) {
      return null;
    }
    return SavedTerm(
      key: key,
      label: label,
      kind: kind,
      description: description,
      intro: intro is String && intro.trim().isNotEmpty ? intro : null,
      own: own is bool ? own : true,
      parts: <SavedStyle>[
        if (parts is List)
          for (final part in parts) ?SavedStyle.fromJson(part),
      ],
      drinks: <TermDrink>{
        if (categories is List)
          for (final drink in TermDrink.values)
            if (categories.contains(drink.wire)) drink,
      },
    );
  }
}

/// 나의 용어 사전: the terms a member saved, newest first.
abstract interface class SavedTermsGateway {
  /// The signed-in member's id; `null` for a visitor, who has no 용어 사전.
  String? get accountId;

  Future<List<SavedTerm>> load();

  /// Saves the term or takes it out, and answers the list as it then is.
  Future<List<SavedTerm>> setSaved(String key, {required bool saved});
}
