class LikedCard {
  const LikedCard({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.recordedAt,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final DateTime recordedAt;
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
  Future<void> like(String cardId);
}
