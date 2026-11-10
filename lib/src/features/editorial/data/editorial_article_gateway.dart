import 'editorial_article.dart';

abstract interface class EditorialArticleGateway {
  Future<List<EditorialArticle>> fetchPublishedArticles();

  Future<List<EditorialArticle>> fetchSavedArticles();

  Future<void> saveArticle(String articleId);

  Future<void> unsaveArticle(String articleId);
}

class EditorialArticleGatewayException implements Exception {
  const EditorialArticleGatewayException(this.operation);

  final EditorialArticleOperation operation;
}

enum EditorialArticleOperation { fetchPublished, fetchSaved, save, unsave }
