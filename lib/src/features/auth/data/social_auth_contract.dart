import '../../../core/errors/connection_failure.dart';

enum SocialAuthProvider { kakao, apple, google }

enum SocialAuthResult { authenticated, redirectStarted }

/// [noSession] is the startup answer when nobody is signed in. [signedOut]
/// is the end of a session, whoever ended it: the app's own sign-out, a
/// renewal the server refused, or another browser tab.
enum SocialAuthSessionEvent { initialSession, signedIn, noSession, signedOut }

abstract interface class SocialAuthGateway {
  Stream<SocialAuthSessionEvent> get sessionEvents;

  /// The provider of the current session, or null when signed out.
  SocialAuthProvider? get signedInProvider;

  Future<SocialAuthResult> signIn(SocialAuthProvider provider);

  Future<void> signOut();
}

class SocialAuthCancelledException implements Exception {
  const SocialAuthCancelledException();
}

/// A login that did not finish. [cause] is what stopped it: the error the
/// provider's SDK or the auth server gave, or the app's own reason.
class SocialAuthException implements Exception, RewordedFailure {
  const SocialAuthException(this.provider, {this.cause});

  final SocialAuthProvider provider;
  @override
  final Object? cause;

  /// Read in the error report, which has nothing else to tell one failed
  /// login from another.
  @override
  String toString() =>
      'SocialAuthException(${provider.name}): ${cause ?? 'no cause given'}';
}

/// A login that came back to the app from the provider's page and could
/// not be finished. It arrives among the session's errors, where the auth
/// client's own failures arrive too: this type tells it apart from a
/// sign-in the client could not renew while offline, which the client tries
/// again by itself and nobody needs telling of.
class ReturnedLoginFailure implements Exception, RewordedFailure {
  const ReturnedLoginFailure(this.cause);

  @override
  final Object cause;

  @override
  String toString() => 'ReturnedLoginFailure($cause)';
}
