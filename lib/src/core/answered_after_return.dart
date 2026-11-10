import 'dart:async';

import 'package:flutter/widgets.dart';

/// Waits for [pending], an answer another app is expected to send back.
///
/// Some logins hand over to another app and complete only when that app
/// returns an answer; a member who comes back on their own leaves the wait
/// open for good. Once this app is in front again and [wait] passes without
/// an answer, the wait ends with what [giveUp] makes. Leaving again stops
/// the clock. An answer that arrives after giving up is dropped.
Future<T> answeredOrGivenUpAfterReturn<T>(
  Future<T> pending, {
  required Object Function() giveUp,
  Duration wait = const Duration(seconds: 20),
}) {
  final done = Completer<T>();
  Timer? clock;
  final lifecycle = AppLifecycleListener(
    onResume: () {
      clock?.cancel();
      clock = Timer(wait, () {
        if (!done.isCompleted) done.completeError(giveUp(), StackTrace.current);
      });
    },
    onInactive: () => clock?.cancel(),
  );
  pending.then(
    (value) {
      if (!done.isCompleted) done.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    },
  );
  return done.future.whenComplete(() {
    clock?.cancel();
    lifecycle.dispose();
  });
}
