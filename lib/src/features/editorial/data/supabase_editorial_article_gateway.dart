import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/kept_first.dart';
import '../../../core/saved_views.dart';
import 'editorial_article.dart';
import 'editorial_article_gateway.dart';
import 'editorial_media_rows.dart';

class SupabaseEditorialArticleGateway
    implements
        EditorialArticleGateway,
        RereadsPublishedArticles,
        KeepsLast<List<EditorialArticle>> {
  SupabaseEditorialArticleGateway(this._client, {this.saved});

  final SupabaseClient _client;

  /// Where the last list of posts is kept for the next launch; `null` keeps
  /// none.
  final SavedViews? saved;
  static const _savedName = 'posts';

  @override
  Future<List<EditorialArticle>?> kept() async {
    final copy = await saved?.read(_savedName);
    return copy is List ? _articles(copy) : null;
  }

  /// The posts of a server answer, newest first.
  List<EditorialArticle> _articles(List<Object?> rows) {
    final articles = <EditorialArticle>[
      for (final value in rows)
        _articleFromMap(Map<String, dynamic>.from(value! as Map)),
    ];
    articles.sort(
      (left, right) => right.publishedAt.compareTo(left.publishedAt),
    );
    return List<EditorialArticle>.unmodifiable(articles);
  }

  static const _articleSelect = '''
    id,
    body,
    instagram_url,
    published_at,
    media:editorial_article_media_assets(
      id,
      storage_bucket,
      storage_object_path,
      sort_order
    ),
    interest_links:editorial_article_interests(
      interest_key
    )
  ''';

  /// The published list is the same for every reader and changes only when
  /// an editor publishes. One read serves every screen that asks within
  /// this window: the explore tab and a post's related posts.
  static const _publishedFreshFor = Duration(minutes: 10);
  Future<List<EditorialArticle>>? _published;
  DateTime _publishedReadAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<List<EditorialArticle>> fetchPublishedArticles() {
    final kept = _published;
    if (kept != null &&
        DateTime.now().difference(_publishedReadAt) < _publishedFreshFor) {
      return kept;
    }
    return rereadPublishedArticles();
  }

  /// Asks the server whatever was read before; the screens that ask after
  /// it share this read.
  @override
  Future<List<EditorialArticle>> rereadPublishedArticles() {
    final read = _readPublishedArticles();
    _published = read;
    _publishedReadAt = DateTime.now();
    // A failed read is not kept; the next screen asks again.
    read.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_published, read)) _published = null;
      },
    );
    return read;
  }

  Future<List<EditorialArticle>> _readPublishedArticles() async {
    try {
      final response = await _client
          .from('editorial_articles')
          .select(_articleSelect)
          .eq('status', 'published');
      final articles = _articles(response);
      unawaited(saved?.write(_savedName, response));
      return articles;
    } catch (error) {
      throw EditorialArticleGatewayException(cause: error);
    }
  }

  EditorialArticle _articleFromMap(Map<String, dynamic> value) {
    final interestValues =
        value['interest_links'] as List? ?? const <dynamic>[];
    final interestKeys = <String>[
      for (final rawLink in interestValues)
        (rawLink as Map)['interest_key'] as String,
    ]..sort();
    return EditorialArticle(
      id: value['id'] as String,
      body: value['body'] as String,
      instagramUrl: value['instagram_url'] as String?,
      publishedAt: DateTime.parse(value['published_at'] as String),
      mediaAssets: editorialMediaFromRows(_client, value['media']),
      interestKeys: List<String>.unmodifiable(interestKeys),
    );
  }
}
