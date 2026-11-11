import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'async_shown.dart';

/// A source that can also give back the copy the phone kept of what it last
/// loaded for the signed-in account; `null` when there is none.
abstract interface class KeepsLast<T> {
  Future<T?> kept();
}

/// Loads in two steps so a screen is never empty while the server is asked:
/// what the phone kept from last time is shown at once, then replaced by
/// what the server says now.
///
/// The kept copy is read only when nothing may be on screen yet (the first
/// load after the app starts or after a sign-out), and `future` then completes
/// with it, the first thing there is to show. A later reload keeps showing
/// what it already has and its `future` completes with the server's answer,
/// so a pull-to-refresh waits for the real thing.
abstract class KeptFirstNotifier<T> extends AsyncNotifier<T> {
  /// What the phone kept of this for the signed-in account, if anything.
  Future<T?> kept();

  /// What the server says now.
  Future<T> load();

  @override
  Future<T> build() async {
    // After a sign-out the state still holds the last account's value, and
    // goes on holding it beside an error until a load succeeds.
    var carried = ref.isReload || state.error is FailedSinceSignOut;
    if (carried || !state.hasValue) {
      final last = await _keptOrNull();
      if (last != null && ref.mounted) {
        state = AsyncData<T>(last);
        carried = false;
      }
    }
    try {
      return await load();
    } catch (error, stack) {
      if (!carried) rethrow;
      Error.throwWithStackTrace(FailedSinceSignOut(error), stack);
    }
  }

  Future<T?> _keptOrNull() async {
    try {
      return await kept();
    } catch (_) {
      // A copy that cannot be read is the same as no copy.
      return null;
    }
  }
}
