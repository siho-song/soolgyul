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
  bool _loaded = false;

  /// A toggle was started, so the first read no longer says what is true.
  bool _toggled = false;
  bool _disposed = false;

  bool get saved => _saved;
  bool get saving => _saving;

  /// Whether the first read has answered (or failed); until then the
  /// bookmark does not yet show what the reader saved.
  bool get loaded => _loaded;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    try {
      final saved = await gateway.fetchSavedArticles();
      if (!_toggled) _saved = saved.any((item) => item.id == article.id);
    } catch (_) {
      // Reading stays open without a login; the bookmark just starts empty.
    } finally {
      _loaded = true;
      _notify();
    }
  }

  /// Flips the bookmark and says how it went, so a reader who is not
  /// signed in and one whose request failed are told different things.
  Future<EditorialSaveOutcome> toggle() async {
    if (_saving) return EditorialSaveOutcome.done;
    _saving = true;
    _toggled = true;
    _notify();
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
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

enum EditorialSaveOutcome { done, needsLogin, failed }
