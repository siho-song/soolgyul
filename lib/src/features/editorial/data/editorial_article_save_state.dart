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

  /// Flips the bookmark. Returns `false` when the server refused, which is
  /// how a signed-out reader finds out.
  Future<bool> toggle() async {
    if (_saving) return true;
    _saving = true;
    notifyListeners();
    try {
      if (_saved) {
        await gateway.unsaveArticle(article.id);
      } else {
        await gateway.saveArticle(article.id);
      }
      _saved = !_saved;
      return true;
    } catch (_) {
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
