import '../../editorial/editorial_article.dart';

/// A hashtag on the explore feed: one kind of drink. No tag chosen shows
/// every post.
enum ExploreTag {
  wine('와인', 'wine'),
  whisky('위스키', 'whisky'),
  sake('사케', 'sake'),
  traditional('전통주', 'korean_traditional');

  const ExploreTag(this.label, this.interestKey);

  final String label;
  final String interestKey;

  String get hashtag => '#$label';

  bool matches(EditorialArticle article) => article.hasInterest(interestKey);
}
