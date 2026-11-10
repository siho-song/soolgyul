import 'package:flutter/foundation.dart';

import 'editorial_article.dart';
import 'editorial_article_gateway.dart';

/// Whether the reader has bookmarked one post. The article header's
/// bookmark button reads and toggles it.
class EditorialArticleSaveState extends ChangeNotifier {
  EditorialArticleSaveState({required this.article, required this.gateway}) {
    _load();
  }

  final EditorialArticle article;
  final EditorialArticleGateway gateway;

  bool _saved = false;
  bool _saving = false;

  bool get saved => _saved;
  bool get saving => _saving;

  Future<void> _load() async {
    try {
      final saved = await gateway.fetchSavedArticles();
      _saved = saved.any((item) => item.id == article.id);
      notifyListeners();
    } catch (_) {
      // Reading stays open without a login; the bookmark just starts empty.
    }
  }

  /// Flips the bookmark and says how it went, so a reader who is not
  /// signed in and one whose request failed are told different things.
  Future<EditorialSaveOutcome> toggle() async {
    if (_saving) return EditorialSaveOutcome.done;
    _saving = true;
    notifyListeners();
    try {
      if (_saved) {
        await gateway.unsaveArticle(article.id);
      } else {
        await gateway.saveArticle(article.id);
      }
      _saved = !_saved;
      return EditorialSaveOutcome.done;
    } on EditorialArticleGatewayException catch (error) {
      return error.needsLogin
          ? EditorialSaveOutcome.needsLogin
          : EditorialSaveOutcome.failed;
    } catch (_) {
      return EditorialSaveOutcome.failed;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}

enum EditorialSaveOutcome { done, needsLogin, failed }
