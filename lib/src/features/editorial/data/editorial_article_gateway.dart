import '../../../core/errors/connection_failure.dart';
import 'editorial_article.dart';

abstract interface class EditorialArticleGateway {
  Future<List<EditorialArticle>> fetchPublishedArticles();

  Future<List<EditorialArticle>> fetchSavedArticles();

  Future<void> saveArticle(String articleId);

  Future<void> unsaveArticle(String articleId);
}

/// A gateway that answers [EditorialArticleGateway.fetchPublishedArticles]
/// from a read it made a while ago can also be made to ask the server now,
/// as a reader pulling the list down expects.
abstract interface class RereadsPublishedArticles {
  Future<List<EditorialArticle>> rereadPublishedArticles();
}

class EditorialArticleGatewayException implements Exception, RewordedFailure {
  const EditorialArticleGatewayException(
    this.operation, {
    this.needsLogin = false,
    this.cause,
  });

  final EditorialArticleOperation operation;

  /// Refused because no one is signed in, not because something failed.
  final bool needsLogin;

  /// What the call failed with, when something did fail.
  @override
  final Object? cause;
}

enum EditorialArticleOperation { fetchPublished, fetchSaved, save, unsave }
