import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/kept_first.dart';
import '../../../core/saved_views.dart';
import 'editorial_article.dart';
import 'editorial_article_gateway.dart';

class SupabaseEditorialArticleGateway
    implements EditorialArticleGateway, KeepsLast<List<EditorialArticle>> {
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
  /// this window: the explore tab, a post's related posts, the bookmarks.
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
    } catch (_) {
      throw const EditorialArticleGatewayException(
        EditorialArticleOperation.fetchPublished,
      );
    }
  }

  @override
  Future<List<EditorialArticle>> fetchSavedArticles() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const <EditorialArticle>[];
    }
    try {
      final response = await _client
          .from('user_saved_articles')
          .select('article_id, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      if (response.isEmpty) {
        return const <EditorialArticle>[];
      }
      final savedAtByArticleId = <String, DateTime>{
        for (final value in response)
          if (value['article_id'] case final String articleId)
            articleId: DateTime.parse(value['created_at'] as String),
      };
      final published = await fetchPublishedArticles();
      final saved = <EditorialArticle>[
        for (final article in published)
          if (savedAtByArticleId[article.id] case final DateTime savedAt)
            article.copyWithSavedAt(savedAt),
      ]..sort((left, right) => right.savedAt!.compareTo(left.savedAt!));
      return List<EditorialArticle>.unmodifiable(saved);
    } catch (_) {
      throw const EditorialArticleGatewayException(
        EditorialArticleOperation.fetchSaved,
      );
    }
  }

  @override
  Future<void> saveArticle(String articleId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const EditorialArticleGatewayException(
        EditorialArticleOperation.save,
      );
    }
    try {
      await _client.from('user_saved_articles').upsert(<String, dynamic>{
        'user_id': userId,
        'article_id': articleId,
      });
    } catch (_) {
      throw const EditorialArticleGatewayException(
        EditorialArticleOperation.save,
      );
    }
  }

  @override
  Future<void> unsaveArticle(String articleId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const EditorialArticleGatewayException(
        EditorialArticleOperation.unsave,
      );
    }
    try {
      await _client
          .from('user_saved_articles')
          .delete()
          .eq('user_id', userId)
          .eq('article_id', articleId);
    } catch (_) {
      throw const EditorialArticleGatewayException(
        EditorialArticleOperation.unsave,
      );
    }
  }

  EditorialArticle _articleFromMap(Map<String, dynamic> value) {
    final mediaValues = value['media'] as List? ?? const <dynamic>[];
    final media = <EditorialMediaAsset>[
      for (final rawMedia in mediaValues)
        _mediaFromMap(Map<String, dynamic>.from(rawMedia as Map)),
    ]..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
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
      mediaAssets: List<EditorialMediaAsset>.unmodifiable(media),
      interestKeys: List<String>.unmodifiable(interestKeys),
    );
  }

  EditorialMediaAsset _mediaFromMap(Map<String, dynamic> value) {
    final bucket = value['storage_bucket'] as String;
    final path = value['storage_object_path'] as String;
    return EditorialMediaAsset(
      id: value['id'] as String,
      storageBucket: bucket,
      storageObjectPath: path,
      sortOrder: value['sort_order'] as int,
      publicUrl: bucket == 'flutter-assets'
          ? null
          : _client.storage.from(bucket).getPublicUrl(path),
    );
  }
}
