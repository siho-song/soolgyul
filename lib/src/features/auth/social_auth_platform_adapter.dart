import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_config.dart';
import 'social_auth_contract.dart';

abstract interface class SocialAuthPlatformAdapter {
  bool get isWeb;

  TargetPlatform get targetPlatform;

  Future<SocialAuthResult> signInWithOAuth(SocialAuthProvider provider);

  Future<SocialAuthResult> signInWithKakao();

  Future<SocialAuthResult> signInWithGoogle();

  Future<SocialAuthResult> signInWithApple();

  Future<void> signOut();

  bool isCancellation(Object error);
}

class PluginSocialAuthPlatformAdapter implements SocialAuthPlatformAdapter {
  PluginSocialAuthPlatformAdapter(this._client);

  final SupabaseClient _client;

  final RetryableInitializer _googleInitializer = RetryableInitializer();
  String? _googleRawNonce;

  @override
  bool get isWeb => kIsWeb;

  @override
  TargetPlatform get targetPlatform => defaultTargetPlatform;

  @override
  Future<SocialAuthResult> signInWithOAuth(SocialAuthProvider provider) async {
    final didLaunch = await _client.auth.signInWithOAuth(
      _toSupabaseProvider(provider),
      redirectTo: _oauthRedirectUrl,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );

    if (!didLaunch) {
      throw SocialAuthException(provider);
    }
    return SocialAuthResult.redirectStarted;
  }

  @override
  Future<SocialAuthResult> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    final rawNonce = _googleRawNonce;
    if (idToken == null || rawNonce == null) {
      throw const SocialAuthException(SocialAuthProvider.google);
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      nonce: rawNonce,
    );
    return SocialAuthResult.authenticated;
  }

  Future<void> _ensureGoogleInitialized() {
    return _googleInitializer.run(_initializeGoogle);
  }

  Future<void> _initializeGoogle() async {
    final rawNonce = _client.auth.generateRawNonce();
    _googleRawNonce = rawNonce;

    await GoogleSignIn.instance.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? AppConfig.googleIosClientId
          : null,
      serverClientId: AppConfig.googleWebClientId,
      nonce: _sha256(rawNonce),
    );
  }

  @override
  Future<SocialAuthResult> signInWithKakao() async {
    final rawNonce = _client.auth.generateRawNonce();
    final hashedNonce = _sha256(rawNonce);

    OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      try {
        token = await UserApi.instance.loginWithKakaoTalk(nonce: hashedNonce);
      } catch (error) {
        if (isCancellation(error)) {
          throw const SocialAuthCancelledException();
        }
        token = await UserApi.instance.loginWithKakaoAccount(
          nonce: hashedNonce,
        );
      }
    } else {
      token = await UserApi.instance.loginWithKakaoAccount(nonce: hashedNonce);
    }

    final idToken = token.idToken;
    if (idToken == null) {
      throw const SocialAuthException(SocialAuthProvider.kakao);
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.kakao,
      idToken: idToken,
      accessToken: token.accessToken,
      nonce: rawNonce,
    );
    return SocialAuthResult.authenticated;
  }

  @override
  Future<SocialAuthResult> signInWithApple() async {
    final rawNonce = _client.auth.generateRawNonce();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const <AppleIDAuthorizationScopes>[
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: _sha256(rawNonce),
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const SocialAuthException(SocialAuthProvider.apple);
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    await _saveAppleNameIfProvided(credential);
    return SocialAuthResult.authenticated;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// Fresh provider proof is used only by the account-deletion endpoint.
  /// Never log or persist this map in app state or preferences.
  Future<Map<String, dynamic>> prepareDeletionProof() async {
    final providers =
        _client.auth.currentUser?.identities
            ?.map((identity) => identity.provider)
            .toSet() ??
        <String>{};
    if (providers.isEmpty) throw StateError('로그인이 필요합니다.');
    final proofs = <String, dynamic>{};
    for (final provider in providers) {
      proofs[provider] = await _prepareProviderDeletionProof(provider);
    }
    return {'providers': proofs};
  }

  Future<Map<String, dynamic>> _prepareProviderDeletionProof(
    String provider,
  ) async {
    final session = _client.auth.currentSession;
    if (kIsWeb ||
        (provider == 'apple' && targetPlatform != TargetPlatform.iOS)) {
      if ((_client.auth.currentUser?.identities?.length ?? 0) != 1) {
        throw StateError('여러 소셜 계정의 연결 해제는 모바일 앱에서 진행해주세요.');
      }
      if (provider == 'apple' && session?.providerRefreshToken != null) {
        return {
          'refresh_token': session!.providerRefreshToken,
          'apple_client': 'web',
        };
      }
      if (session?.providerToken != null) {
        return {'access_token': session!.providerToken};
      }
      throw StateError('연결 해제를 위해 소셜 로그인을 다시 진행해주세요.');
    }
    if (provider == 'google') {
      await _ensureGoogleInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      const scopes = ['openid', 'email'];
      final authorization =
          await account.authorizationClient.authorizationForScopes(scopes) ??
          await account.authorizationClient.authorizeScopes(scopes);
      return {'access_token': authorization.accessToken};
    }
    if (provider == 'kakao') {
      final token = await UserApi.instance.loginWithKakaoAccount();
      return {'access_token': token.accessToken};
    }
    if (provider == 'apple') {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [],
      );
      return {
        'authorization_code': credential.authorizationCode,
        'apple_client': 'native',
      };
    }
    throw StateError('지원하지 않는 로그인 방식입니다.');
  }

  Future<void> _saveAppleNameIfProvided(
    AuthorizationCredentialAppleID credential,
  ) async {
    final givenName = credential.givenName?.trim();
    final familyName = credential.familyName?.trim();
    final fullName = <String?>[
      familyName,
      givenName,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');

    if (fullName.isEmpty) {
      return;
    }

    await _client.auth.updateUser(
      UserAttributes(
        data: <String, dynamic>{
          'full_name': fullName,
          if (givenName != null && givenName.isNotEmpty)
            'given_name': givenName,
          if (familyName != null && familyName.isNotEmpty)
            'family_name': familyName,
        },
      ),
    );
  }

  @override
  bool isCancellation(Object error) {
    return (error is GoogleSignInException &&
            (error.code == GoogleSignInExceptionCode.canceled ||
                error.code == GoogleSignInExceptionCode.interrupted)) ||
        (error is SignInWithAppleAuthorizationException &&
            error.code == AuthorizationErrorCode.canceled) ||
        (error is KakaoClientException &&
            error.reason == ClientErrorCause.cancelled) ||
        (error is KakaoAuthException &&
            error.error == AuthErrorCause.accessDenied) ||
        (error is PlatformException &&
            (error.code.toUpperCase() == 'CANCELED' ||
                error.code.toUpperCase() == 'CANCELLED'));
  }

  OAuthProvider _toSupabaseProvider(SocialAuthProvider provider) {
    return switch (provider) {
      SocialAuthProvider.kakao => OAuthProvider.kakao,
      SocialAuthProvider.apple => OAuthProvider.apple,
      SocialAuthProvider.google => OAuthProvider.google,
    };
  }

  String get _oauthRedirectUrl {
    if (!kIsWeb) {
      return AppConfig.authRedirectUrl;
    }

    return Uri.parse(AppConfig.webUrl).resolve('/auth/callback').toString();
  }

  String _sha256(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}

@visibleForTesting
final class RetryableInitializer {
  Future<void>? _cachedAttempt;

  Future<void> run(Future<void> Function() initialize) {
    final cachedAttempt = _cachedAttempt;
    if (cachedAttempt != null) {
      return cachedAttempt;
    }

    late final Future<void> guardedAttempt;
    guardedAttempt = Future<void>.sync(initialize).onError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (identical(_cachedAttempt, guardedAttempt)) {
        _cachedAttempt = null;
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
    _cachedAttempt = guardedAttempt;
    return guardedAttempt;
  }
}
