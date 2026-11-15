/// The drinks a term belongs to, as 나의 용어 사전 filters by them.
enum TermDrink {
  /// A term of every drink: a scent, a taste, a texture.
  common('common', '공통'),
  wine('wine', '와인'),
  whisky('whisky', '위스키'),
  sake('sake', '사케'),
  koreanTraditional('korean_traditional', '전통주');

  const TermDrink(this.wire, this.label);

  final String wire;
  final String label;
}

/// A term the reader saved from its help balloon, as the dictionary explains
/// it now.
class SavedTerm {
  const SavedTerm({
    required this.key,
    required this.label,
    required this.kind,
    required this.drinks,
    required this.description,
  });

  /// The dictionary's key of the term (aroma:cherry).
  final String key;
  final String label;

  /// 향, 맛, 질감, 여운, 제조·숙성, 품종, 산지, 생산자.
  final String kind;

  /// Empty when the dictionary does not say which drinks the term is of.
  final Set<TermDrink> drinks;
  final String description;

  static SavedTerm? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final label = json['label'];
    final kind = json['kind'];
    final description = json['description'];
    final categories = json['categories'];
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
