class LikedCard {
  const LikedCard({
    required this.id,
    required this.title,
    required this.category,
    required this.recordedAt,
    required this.likedAt,
    this.resultId,
    this.summary,
    this.note,
    this.imageUrl,
  });

  /// The liked record's id, which a like is keyed by.
  final String id;

  /// The card to open; `null` for a record without one.
  final String? resultId;
  final String title;

  /// The card's one line, as the 취향 tab shows it; `null` without one.
  final String? summary;

  /// The reader's one-line note; `null` without one.
  final String? note;
  final String category;
  final DateTime recordedAt;
  final DateTime likedAt;
  final String? imageUrl;
}

class LikedCardsPage {
  const LikedCardsPage({required this.cards, required this.total});
  final List<LikedCard> cards;
  final int total;
}

abstract interface class LikedCardsGateway {
  Future<LikedCardsPage> fetch({
    String? category,
    bool latestFirst = true,
    int offset = 0,
  });

  Future<void> unlike(String cardId);
  Future<bool> isLiked(String cardId);

  /// [likedAt] keeps an undone unlike in its old place in the list.
  Future<void> like(String cardId, {DateTime? likedAt});
}
