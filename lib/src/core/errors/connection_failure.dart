import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../async_shown.dart';

/// A request to the server that the connection failed: nothing could be
/// sent, or no answer came within the request's time limit. Every request
/// passes [TimeLimitedClient], which throws this in place of whatever the
/// platform threw, so one type says it on the phone and on the web.
///
/// Deliberately an [Error], not an [Exception]: the database client asks
/// again any read that failed with an Exception, three more times with 1, 2
/// and 4 seconds between, before the screen hears of it. A phone without a
/// connection has none a second later either; this passes through that
/// retry, and the screen says so after the first failure.
final class ConnectionFailure extends Error {
  ConnectionFailure(this.cause);

  /// What the platform's client failed with, or the time limit's own
  /// [TimeoutException].
  final Object cause;

  @override
  String toString() => 'ConnectionFailure($cause)';
}

/// A failure a gateway rewords on its way to the screen (its own exception,
/// with the operation or the server's code). It keeps what it was told in
/// [cause], so the screen can still tell a dead connection from a refusal.
abstract interface class RewordedFailure {
  Object? get cause;
}

/// Whether [error] is the connection failing, not the server or the app:
/// no route, a socket or handshake that broke, a time limit that ran out.
/// What a screen shows for it is the connection's own wording
/// (widgets/app_state_view.dart), and it is not worth a report.
///
/// On the web an unreachable server and an offline browser look the same.
/// No error at all is no connection failure.
bool isConnectionFailure(Object? error) {
  if (error == null) return false;
  if (error is FailedSinceSignOut) return isConnectionFailure(error.cause);
  if (error is RewordedFailure) return isConnectionFailure(error.cause);
  if (error is ConnectionFailure ||
      error is TimeoutException ||
      // The auth client's word for a request it could not get through.
      error is AuthRetryableFetchException) {
    return true;
  }
  // By name: dart:io is not there on the web.
  final type = error.runtimeType.toString();
  return const <String>{
        'SocketException',
        'ClientException',
        'HandshakeException',
        'HttpException',
      }.contains(type) ||
      type.startsWith('_ClientSocketException');
}
