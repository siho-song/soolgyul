import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const webUrl = String.fromEnvironment('APP_WEB_URL');

  /// Where errors are collected. Empty leaves collection off.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// Only the released product is counted. A debug run started with
  /// SOOL_ANALYTICS=on is counted too, to watch the counts arrive.
  static const countsUsage =
      (environment == 'production' && kReleaseMode) ||
      (kDebugMode && String.fromEnvironment('SOOL_ANALYTICS') == 'on');
  static const authRedirectUrl = String.fromEnvironment('AUTH_REDIRECT_URL');

  /// The app's App Store page.
  static const appStoreUrl = 'https://apps.apple.com/kr/app/id6834264062';

  /// The Play page when it is not the one of the installed package; empty
  /// otherwise.
  static const playStoreUrl = String.fromEnvironment('PLAY_STORE_URL');

  /// Where the web's card link lives: the intro site, so a phone with the
  /// app opens the link in the app and one without it reaches the store.
  static const claimLinkBaseUrl = String.fromEnvironment(
    'CLAIM_LINK_URL',
    defaultValue: 'https://soolgyul.com',
  );
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const googleAndroidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );
  static const googleIosUrlScheme = String.fromEnvironment(
    'GOOGLE_IOS_URL_SCHEME',
  );
  static const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
  );
  static const kakaoNativeAppScheme = String.fromEnvironment(
    'KAKAO_NATIVE_APP_SCHEME',
  );

  static void validateSupabase() {
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required.',
      );
    }
  }

  static void validateSocialAuth() {
    if (googleWebClientId.isEmpty ||
        googleAndroidClientId.isEmpty ||
        googleIosClientId.isEmpty ||
        googleIosUrlScheme.isEmpty ||
        kakaoNativeAppKey.isEmpty ||
        kakaoNativeAppScheme.isEmpty) {
      throw StateError(
        'Google and Kakao public client configuration is required.',
      );
    }
  }
}
