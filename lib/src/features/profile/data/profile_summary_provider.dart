import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'profile_summary.dart';

/// Reads the My Page counts from the server; `null` runs without them.
final profileSummaryLoaderProvider = Provider<ProfileSummaryLoader?>(
  (ref) => null,
);

/// The My Page counts, kept for the whole session. They load once after
/// sign-in and again only when the app saves or removes something they
/// count; opening My Page reads what is here.
final profileSummaryProvider =
    NotifierProvider<ProfileSummaryNotifier, ProfileSummaryState>(
      ProfileSummaryNotifier.new,
    );

@immutable
class ProfileSummaryState {
  const ProfileSummaryState({
    this.summary,
    this.failed = false,
    this.loading = false,
  });

  final ProfileSummary? summary;
  final bool failed;
  final bool loading;

  /// Whether My Page still has to ask: nothing loaded and nothing on the way.
  bool get needsLoad => summary == null && !loading && !failed;
}

class ProfileSummaryNotifier extends Notifier<ProfileSummaryState> {
  int _request = 0;

  @override
  ProfileSummaryState build() => const ProfileSummaryState();

  /// Fetches the counts; the old ones stay on screen until the new arrive.
  /// Throws what the loader throws, after marking the failure.
  Future<ProfileSummary?> load() async {
    final loader = ref.read(profileSummaryLoaderProvider);
    if (loader == null) return null;
    final request = ++_request;
    state = ProfileSummaryState(summary: state.summary, loading: true);
    var summary = state.summary;
    var failed = false;
    try {
      final loaded = await loader();
      if (request == _request) summary = loaded;
      return loaded;
    } catch (_) {
      if (request == _request) failed = true;
      rethrow;
    } finally {
      if (request == _request && ref.mounted) {
        state = ProfileSummaryState(summary: summary, failed: failed);
      }
    }
  }

  /// [load] for callers that only want the counts kept fresh.
  void refresh() => load().ignore();

  /// Forgets the counts of the account that signed out.
  void clear() {
    _request++;
    state = const ProfileSummaryState();
  }
}
