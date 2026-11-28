import '../../../core/errors/connection_failure.dart';
import 'editorial_article.dart';

abstract interface class EditorialArticleGateway {
  Future<List<EditorialArticle>> fetchPublishedArticles();
}

/// A gateway that answers [EditorialArticleGateway.fetchPublishedArticles]
/// from a read it made a while ago can also be made to ask the server now,
/// as a reader pulling the list down expects.
abstract interface class RereadsPublishedArticles {
  Future<List<EditorialArticle>> rereadPublishedArticles();
}

/// The published posts could not be read.
class EditorialArticleGatewayException implements Exception, RewordedFailure {
  const EditorialArticleGatewayException({this.cause});

  /// What the read failed with.
  @override
  final Object? cause;
}
