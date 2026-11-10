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

class SocialAuthException implements Exception {
  const SocialAuthException(this.provider);

  final SocialAuthProvider provider;
}
