import 'package:flutter/foundation.dart';

import 'profile_summary.dart';

/// The My Page counts, kept for the whole session. They load once after
/// sign-in and again only when the app saves or removes something they
/// count; opening My Page reads what is here.
class ProfileSummaryStore extends ChangeNotifier {
  ProfileSummaryStore(this._loader);

  final ProfileSummaryLoader? _loader;

  ProfileSummary? _summary;
  bool _failed = false;
  bool _loading = false;
  int _request = 0;
  bool _disposed = false;

  ProfileSummary? get summary => _summary;
  bool get failed => _failed;

  /// Whether My Page still has to ask: nothing loaded and nothing on the way.
  bool get needsLoad => _summary == null && !_loading && !_failed;

  /// Fetches the counts; the old ones stay on screen until the new arrive.
  /// Throws what the loader throws, after marking the failure.
  Future<ProfileSummary?> load() async {
    final loader = _loader;
    if (loader == null) return null;
    final request = ++_request;
    _loading = true;
    _failed = false;
    notifyListeners();
    try {
      final summary = await loader();
      if (request == _request) _summary = summary;
      return summary;
    } catch (_) {
      if (request == _request) _failed = true;
      rethrow;
    } finally {
      if (request == _request && !_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// [load] for callers that only want the counts kept fresh.
  void refresh() => load().ignore();

  /// Forgets the counts of the account that signed out.
  void clear() {
    _request++;
    _summary = null;
    _failed = false;
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
