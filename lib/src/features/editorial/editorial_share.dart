import 'package:share_plus/share_plus.dart';

import '../../config/app_config.dart';
import 'data/editorial_article.dart';

/// What the system share sheet sends for a post: its first line, then where
/// 술결 lives. A post has no page of its own on the web yet, so the link is
/// the intro site, which opens the app or leads to the store.
String editorialShareText(EditorialArticle article) {
  final headline = article.body
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  return <String>[
    if (headline.isNotEmpty) headline,
    '술결에서 보기 ${AppConfig.claimLinkBaseUrl}',
  ].join('\n\n');
}

/// Opens the phone's own share sheet (iOS share sheet, Android chooser; the
/// browser's share dialog on the web) for the post.
Future<void> shareEditorialArticle(EditorialArticle article) =>
    SharePlus.instance.share(ShareParams(text: editorialShareText(article)));
