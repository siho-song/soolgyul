enum SocialAuthProvider { kakao, apple, google }

enum SocialAuthResult { authenticated, redirectStarted }

/// [noSession] is the startup answer when nobody is signed in.
enum SocialAuthSessionEvent { initialSession, signedIn, noSession }

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
