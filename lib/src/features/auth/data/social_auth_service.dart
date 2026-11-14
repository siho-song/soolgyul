import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_config.dart';
import 'social_auth_contract.dart';
import 'social_auth_platform_adapter.dart';

export 'social_auth_contract.dart';

class SocialAuthService implements SocialAuthGateway {
  /// [returnLinks] are the links the phone opens in the app. One that is
  /// [returnUrl] finishes a login started on the provider's page.
  SocialAuthService(
    this._client, {
    SocialAuthPlatformAdapter? platformAdapter,
    Stream<Uri>? returnLinks,
    String returnUrl = AppConfig.authRedirectUrl,
  }) : _platformAdapter =
           platformAdapter ?? PluginSocialAuthPlatformAdapter(_client) {
    final own = Uri.parse(returnUrl);
    returnLinks
        ?.where(
          // The return from KakaoTalk (`kakao<key>://oauth?code=…`) carries
          // a code too, and is the Kakao SDK's to finish.
          (link) =>
              link.scheme == own.scheme &&
              link.host == own.host &&
              link.path == own.path,
        )
        // A link that could not be read is reported where links are read.
        .listen(_finishReturnedLogin, onError: (Object _) {});
  }

  final SupabaseClient _client;
  final SocialAuthPlatformAdapter _platformAdapter;

  /// Logins that came back to the app and could not be finished.
  final _returnFailures = StreamController<SocialAuthSessionEvent>.broadcast();

  Future<void> _finishReturnedLogin(Uri link) async {
    try {
      await _client.auth.getSessionFromUrl(link);
    } catch (error, stack) {
      _returnFailures.addError(error, stack);
    }
  }

  /// A login that could not be finished after its return arrives as an
  /// error, like the auth client's own failures.
  @override
  Stream<SocialAuthSessionEvent> get sessionEvents {
    late final StreamController<SocialAuthSessionEvent> events;
    final sources = <StreamSubscription<SocialAuthSessionEvent>>[];
    events = StreamController<SocialAuthSessionEvent>(
      onListen: () {
        for (final source in [_sessionChanges, _returnFailures.stream]) {
          sources.add(source.listen(events.add, onError: events.addError));
        }
      },
      onCancel: () => Future.wait(sources.map((source) => source.cancel())),
    );
    return events.stream;
  }

  Stream<SocialAuthSessionEvent> get _sessionChanges {
    return _client.auth.onAuthStateChange
        .map((state) {
          return switch ((state.event, state.session)) {
            (AuthChangeEvent.initialSession, null) =>
              SocialAuthSessionEvent.noSession,
            (AuthChangeEvent.initialSession, _) =>
              SocialAuthSessionEvent.initialSession,
            (AuthChangeEvent.signedIn, _?) => SocialAuthSessionEvent.signedIn,
            (AuthChangeEvent.signedOut, _) => SocialAuthSessionEvent.signedOut,
            _ => null,
          };
        })
        .where((event) => event != null)
        .cast<SocialAuthSessionEvent>();
  }

  @override
  SocialAuthProvider? get signedInProvider {
    final provider = _client.auth.currentUser?.appMetadata['provider'];
    return SocialAuthProvider.values
        .where((value) => value.name == provider)
        .firstOrNull;
  }

  @override
  Future<SocialAuthResult> signIn(SocialAuthProvider provider) async {
    try {
      if (_platformAdapter.isWeb) {
        return await _platformAdapter.signInWithOAuth(provider);
      }

      return await switch ((provider, _platformAdapter.targetPlatform)) {
        (SocialAuthProvider.kakao, TargetPlatform.android) ||
        (
          SocialAuthProvider.kakao,
          TargetPlatform.iOS,
        ) => _platformAdapter.signInWithKakao(),
        (SocialAuthProvider.google, TargetPlatform.android) ||
        (
          SocialAuthProvider.google,
          TargetPlatform.iOS,
        ) => _platformAdapter.signInWithGoogle(),
        (SocialAuthProvider.apple, TargetPlatform.iOS) =>
          _platformAdapter.signInWithApple(),
        _ => _platformAdapter.signInWithOAuth(provider),
      };
    } on SocialAuthCancelledException {
      rethrow;
    } catch (error) {
      if (_platformAdapter.isCancellation(error)) {
        throw const SocialAuthCancelledException();
      }
      throw SocialAuthException(provider);
    }
  }

  @override
  Future<void> signOut() => _platformAdapter.signOut();

  Future<Map<String, dynamic>> prepareDeletionProof() {
    final adapter = _platformAdapter;
    if (adapter is PluginSocialAuthPlatformAdapter) {
      return adapter.prepareDeletionProof();
    }
    throw StateError('social unlinking is not configured');
  }
}
