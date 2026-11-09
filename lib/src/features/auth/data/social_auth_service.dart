import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'social_auth_contract.dart';
import 'social_auth_platform_adapter.dart';

export 'social_auth_contract.dart';

class SocialAuthService implements SocialAuthGateway {
  SocialAuthService(this._client, {SocialAuthPlatformAdapter? platformAdapter})
    : _platformAdapter =
          platformAdapter ?? PluginSocialAuthPlatformAdapter(_client);

  final SupabaseClient _client;
  final SocialAuthPlatformAdapter _platformAdapter;

  @override
  Stream<SocialAuthSessionEvent> get sessionEvents {
    return _client.auth.onAuthStateChange
        .map((state) {
          return switch ((state.event, state.session)) {
            (AuthChangeEvent.initialSession, null) =>
              SocialAuthSessionEvent.noSession,
            (AuthChangeEvent.initialSession, _) =>
              SocialAuthSessionEvent.initialSession,
            (AuthChangeEvent.signedIn, _?) => SocialAuthSessionEvent.signedIn,
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
    throw StateError('소셜 연결 해제 기능이 설정되지 않았습니다.');
  }
}
