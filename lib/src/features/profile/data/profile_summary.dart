typedef ProfileSummaryLoader = Future<ProfileSummary> Function();

class ProfileSummary {
  const ProfileSummary({
    required this.cardCount,
    required this.savedArticleCount,
    required this.likedCardCount,
  });

  final int cardCount;
  final int savedArticleCount;
  final int likedCardCount;
}
