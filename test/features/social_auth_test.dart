import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:soolgyul/src/features/auth/social_auth_platform_adapter.dart';
import 'package:soolgyul/src/features/auth/social_auth_service.dart';
import 'package:soolgyul/src/features/onboarding/presentation/auth/login_screen.dart';
import 'package:soolgyul/src/features/onboarding/presentation/auth/social_login_actions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/app_test_harness.dart';

void main() {
  group('SocialAuthService', () {
    late SupabaseClient client;

    setUp(() {
      client = SupabaseClient('https://example.supabase.co', 'test-anon-key');
    });

    tearDown(() async {
      await client.dispose();
    });

    test('web always uses the OAuth flow', () async {
      final adapter = _FakeSocialAuthPlatformAdapter(isWeb: true);
      final service = SocialAuthService(client, platformAdapter: adapter);

      for (final provider in SocialAuthProvider.values) {
        expect(
          await service.signIn(provider),
          SocialAuthResult.redirectStarted,
        );
      }

      expect(adapter.calls, <String>[
        'oauth:kakao',
        'oauth:apple',
        'oauth:google',
      ]);
    });

    test('mobile providers use native flows only where supported', () async {
      final androidAdapter = _FakeSocialAuthPlatformAdapter(
        targetPlatform: TargetPlatform.android,
      );
      final androidService = SocialAuthService(
        client,
        platformAdapter: androidAdapter,
      );

      await androidService.signIn(SocialAuthProvider.kakao);
      await androidService.signIn(SocialAuthProvider.google);
      await androidService.signIn(SocialAuthProvider.apple);

      expect(androidAdapter.calls, <String>[
        'native:kakao',
        'native:google',
        'oauth:apple',
      ]);

      final iosAdapter = _FakeSocialAuthPlatformAdapter(
        targetPlatform: TargetPlatform.iOS,
      );
      final iosService = SocialAuthService(client, platformAdapter: iosAdapter);

      await iosService.signIn(SocialAuthProvider.apple);

      expect(iosAdapter.calls, <String>['native:apple']);
    });

    test('provider cancellation is normalized', () async {
      final adapter = _FakeSocialAuthPlatformAdapter(
        nextError: const _ProviderCancellation(),
      );
      final service = SocialAuthService(client, platformAdapter: adapter);

      await expectLater(
        service.signIn(SocialAuthProvider.kakao),
        throwsA(isA<SocialAuthCancelledException>()),
      );
    });

    test('provider failures include the requested provider', () async {
      final adapter = _FakeSocialAuthPlatformAdapter(
        nextError: StateError('provider failed'),
      );
      final service = SocialAuthService(client, platformAdapter: adapter);

      await expectLater(
        service.signIn(SocialAuthProvider.google),
        throwsA(
          isA<SocialAuthException>().having(
            (error) => error.provider,
            'provider',
            SocialAuthProvider.google,
          ),
        ),
      );
    });

    test('sign out is delegated to the auth adapter', () async {
      final adapter = _FakeSocialAuthPlatformAdapter();
      final service = SocialAuthService(client, platformAdapter: adapter);

      await service.signOut();

      expect(adapter.calls, <String>['sign-out']);
    });

    test('plugin adapter recognizes platform cancellation codes', () {
      final adapter = PluginSocialAuthPlatformAdapter(client);

      expect(
        adapter.isCancellation(PlatformException(code: 'CANCELED')),
        isTrue,
      );
      expect(
        adapter.isCancellation(PlatformException(code: 'CANCELLED')),
        isTrue,
      );
      expect(
        adapter.isCancellation(PlatformException(code: 'FAILED')),
        isFalse,
      );
    });

    test('plugin adapter classifies every native provider cancellation', () {
      final adapter = PluginSocialAuthPlatformAdapter(client);
      final cancellations = <Object>[
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.interrupted,
        ),
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'cancelled',
        ),
        KakaoClientException(ClientErrorCause.cancelled, 'cancelled'),
        KakaoAuthException(AuthErrorCause.accessDenied, 'cancelled'),
      ];
      final failures = <Object>[
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.failed,
          message: 'failed',
        ),
        KakaoClientException(ClientErrorCause.unknown, 'failed'),
        KakaoAuthException(AuthErrorCause.serverError, 'failed'),
      ];

      for (final error in cancellations) {
        expect(adapter.isCancellation(error), isTrue, reason: '$error');
      }
      for (final error in failures) {
        expect(adapter.isCancellation(error), isFalse, reason: '$error');
      }
    });

    test(
      'failed initialization can retry and caches the later success',
      () async {
        final initializer = RetryableInitializer();
        var attempts = 0;

        Future<void> initialize() async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('temporary initialization failure');
          }
        }

        await expectLater(initializer.run(initialize), throwsStateError);
        await initializer.run(initialize);
        await initializer.run(initialize);

        expect(attempts, 2);
      },
    );
  });

  group('SocialLoginActions', () {
    testWidgets('ignores a second provider while login is pending', (
      tester,
    ) async {
      final completer = Completer<void>();
      final requestedProviders = <SocialAuthProvider>[];
      await _pumpLoginActions(
        tester,
        onLogin: (provider) {
          requestedProviders.add(provider);
          return completer.future;
        },
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('kakao-login-button')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('google-login-button')),
      );
      await tester.pump();

      expect(requestedProviders, <SocialAuthProvider>[
        SocialAuthProvider.kakao,
      ]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('cancellation restores buttons without an error message', (
      tester,
    ) async {
      var attempts = 0;
      await _pumpLoginActions(
        tester,
        onLogin: (_) async {
          attempts += 1;
          throw const SocialAuthCancelledException();
        },
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('kakao-login-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('kakao-login-button')),
      );
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('failure shows feedback and allows a retry', (tester) async {
      var attempts = 0;
      await _pumpLoginActions(
        tester,
        onLogin: (_) async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('provider failed');
          }
        },
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('google-login-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('로그인에 실패했어요. 잠시 후 다시 시도해주세요.'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('google-login-button')),
      );
      await tester.pumpAndSettle();

      expect(attempts, 2);
    });
  });

  group('OnboardingLoginScreen', () {
    Offset top(WidgetTester tester, String key) =>
        tester.getTopLeft(find.byKey(ValueKey<String>(key)));

    testWidgets('Android lists Kakao, Google, then Apple', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final requestedProviders = <SocialAuthProvider>[];
      await pumpTestScreen(
        tester,
        OnboardingLoginScreen(
          onLogin: (provider) async => requestedProviders.add(provider),
        ),
      );

      expect(find.bySemanticsLabel('카카오 로그인'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('kakao-login-artwork')),
        findsOneWidget,
      );
      expect(find.text('Apple로 계속하기'), findsOneWidget);
      expect(find.text('Google로 계속하기'), findsOneWidget);
      expect(find.text('구글로 시작하기'), findsNothing);
      expect(
        top(tester, 'kakao-login-button').dy,
        lessThan(top(tester, 'google-login-button').dy),
      );
      expect(
        top(tester, 'google-login-button').dy,
        lessThan(top(tester, 'apple-login-button').dy),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('kakao-login-button')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('apple-login-button')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('google-login-button')),
      );
      await tester.pump();

      expect(requestedProviders, <SocialAuthProvider>[
        SocialAuthProvider.kakao,
        SocialAuthProvider.apple,
        SocialAuthProvider.google,
      ]);
      // The binding checks this before tear-downs run; the tearDown above
      // only covers a failure part-way through.
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS lists Kakao, Apple, then Google', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpTestScreen(
        tester,
        OnboardingLoginScreen(onLogin: (_) async {}),
      );

      expect(
        top(tester, 'kakao-login-button').dy,
        lessThan(top(tester, 'apple-login-button').dy),
      );
      expect(
        top(tester, 'apple-login-button').dy,
        lessThan(top(tester, 'google-login-button').dy),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

Future<void> _pumpLoginActions(
  WidgetTester tester, {
  required Future<void> Function(SocialAuthProvider provider) onLogin,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: SocialLoginActions(onLogin: onLogin),
          ),
        ),
      ),
    ),
  );
}

class _ProviderCancellation {
  const _ProviderCancellation();
}

class _FakeSocialAuthPlatformAdapter implements SocialAuthPlatformAdapter {
  _FakeSocialAuthPlatformAdapter({
    this.isWeb = false,
    this.targetPlatform = TargetPlatform.android,
    this.nextError,
  });

  @override
  final bool isWeb;

  @override
  final TargetPlatform targetPlatform;

  final Object? nextError;
  final List<String> calls = <String>[];

  @override
  Future<SocialAuthResult> signInWithApple() {
    return _complete('native:apple', SocialAuthResult.authenticated);
  }

  @override
  Future<SocialAuthResult> signInWithGoogle() {
    return _complete('native:google', SocialAuthResult.authenticated);
  }

  @override
  Future<SocialAuthResult> signInWithKakao() {
    return _complete('native:kakao', SocialAuthResult.authenticated);
  }

  @override
  Future<SocialAuthResult> signInWithOAuth(SocialAuthProvider provider) {
    return _complete(
      'oauth:${provider.name}',
      SocialAuthResult.redirectStarted,
    );
  }

  @override
  Future<void> signOut() async {
    calls.add('sign-out');
    final error = nextError;
    if (error != null) {
      throw error;
    }
  }

  @override
  bool isCancellation(Object error) => error is _ProviderCancellation;

  Future<SocialAuthResult> _complete(
    String call,
    SocialAuthResult result,
  ) async {
    calls.add(call);
    final error = nextError;
    if (error != null) {
      throw error;
    }
    return result;
  }
}
