import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A load that failed while its provider still carried what it had loaded
/// before a sign-out. Riverpod keeps an earlier value beside any later
/// error, so this error is what says the value belongs to the last account.
class FailedSinceSignOut implements Exception {
  const FailedSinceSignOut(this.cause);

  /// What the load itself failed with.
  final Object cause;

  @override
  String toString() => 'FailedSinceSignOut($cause)';
}

/// What a screen may show of [value]: the loaded data, kept while it loads
/// again after a change, but not across a sign-out (a reload), where the
/// next account must not see the last one's data: neither while its own
/// loads nor when that load fails.
T? shownValue<T>(AsyncValue<T> value) =>
    value.isReloading || value.error is FailedSinceSignOut ? null : value.value;
