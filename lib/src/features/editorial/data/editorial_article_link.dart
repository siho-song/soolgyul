/// A post's link on the intro site. A phone with the app opens it in the
/// app, on that post; without the app the link's page leads to the store,
/// and on Android the post id rides into the fresh install as the Play
/// install referrer.
abstract final class EditorialArticleLink {
  static const path = '/article';

  static Uri build(String baseUrl, String articleId) => Uri.parse(
    baseUrl,
  ).replace(path: path, queryParameters: <String, String>{'id': articleId});

  /// The post id in a link, or `null` for any other link. The site answers
  /// with a trailing slash, so both spellings of the path count.
  static String? parse(Uri uri) {
    if (uri.path != path && uri.path != '$path/') return null;
    final id = uri.queryParameters['id'];
    return id == null || id.isEmpty ? null : id;
  }

  /// What the link's page hands the Play store, so a fresh install still
  /// knows the post.
  static const referrerKey = 'article';

  /// The post id the Play store handed a fresh install, or `null`.
  static String? parseInstallReferrer(String? referrer) {
    if (referrer == null || referrer.isEmpty) return null;
    try {
      final id = Uri.splitQueryString(referrer)[referrerKey];
      return id == null || id.isEmpty ? null : id;
    } on ArgumentError {
      return null;
    }
  }
}
