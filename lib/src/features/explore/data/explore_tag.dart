import '../../../core/catalog/drink_type.dart';
import '../../editorial/data/editorial_article.dart';

/// A hashtag on the explore feed: one 주종. No tag chosen shows every post.
typedef ExploreTag = DrinkType;

extension ExploreTagText on DrinkType {
  String get hashtag => '#$label';

  bool matches(EditorialArticle article) => article.hasInterest(key);
}
