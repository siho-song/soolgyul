import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app/app.dart';
import 'src/app/asset_warmup.dart';
import 'src/config/app_config.dart';
import 'src/features/auth/data/social_auth_service.dart';
import 'src/features/catalog/data/supabase_catalog_search_gateway.dart';
import 'src/features/editorial/data/supabase_editorial_article_gateway.dart';
import 'src/features/home/data/supabase_next_drink_guides_gateway.dart';
import 'src/features/home/data/supabase_taste_letters_gateway.dart';
import 'src/features/preferences/data/supabase_preference_history_gateway.dart';
import 'src/features/profile/data/supabase_profile_preferences_gateway.dart';
import 'src/features/profile/data/supabase_profile_summary.dart';
import 'src/features/profile/data/supabase_liked_cards_gateway.dart';
import 'src/features/profile/data/supabase_support_inquiry_gateway.dart';
import 'src/features/profile/data/marketing_consent_gateway.dart';
import 'src/features/profile/data/supabase_account_completion_gateway.dart';
import 'src/features/profile/data/account_deletion_gateway.dart';
import 'src/features/records/data/supabase_record_note_gateway.dart';
import 'src/features/taste_card/data/supabase_taste_card_gateway.dart';
import 'src/features/taste_fit/data/supabase_taste_fit_gateway.dart';
import 'src/widgets/browser_safe_area.dart';

export 'src/app/app.dart';
export 'src/app/app_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enableBrowserSafeArea();
  AppConfig.validateSupabase();
  // Web logs in through Supabase OAuth redirects; the native client IDs are
  // only needed by the phone SDKs.
  if (!kIsWeb) AppConfig.validateSocialAuth();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await KakaoSdk.init(
      nativeAppKey: AppConfig.kakaoNativeAppKey,
      customScheme: AppConfig.kakaoNativeAppScheme,
    );
  }

  final supabaseClient = Supabase.instance.client;
  await _signInTestUser(supabaseClient);
  final socialAuth = SocialAuthService(supabaseClient);
  runApp(
    AssetWarmup(
      child: App(
        incomingLinks: _incomingLinks(),
        installReferrer:
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? _readInstallReferrerOnce
            : null,
        socialAuthGateway: socialAuth,
        accountDeletionGateway: SupabaseAccountDeletionGateway(
          supabaseClient,
          loadProviderProof: socialAuth.prepareDeletionProof,
        ),
        profileSummaryLoader: SupabaseProfileSummary(supabaseClient).load,
        likedCardsGateway: SupabaseLikedCardsGateway(supabaseClient),
        recordNoteGateway: SupabaseRecordNoteGateway(supabaseClient),
        supportInquiryGateway: SupabaseSupportInquiryGateway(supabaseClient),
        marketingConsentGateway: SupabaseMarketingConsentGateway(
          supabaseClient,
        ),
        profilePreferencesGateway: SupabaseProfilePreferencesGateway(
          supabaseClient,
        ),
        accountCompletionGateway: SupabaseAccountCompletionGateway(
          supabaseClient,
        ),
        editorialArticleGateway: SupabaseEditorialArticleGateway(
          supabaseClient,
        ),
        catalogSearchGateway: SupabaseCatalogSearchGateway(supabaseClient),
        tasteCardGateway: SupabaseTasteCardGateway(supabaseClient),
        tasteFitGateway: SupabaseTasteFitGateway(supabaseClient),
        tasteLettersGateway: SupabaseTasteLettersGateway(supabaseClient),
        nextDrinkGuidesGateway: SupabaseNextDrinkGuidesGateway(supabaseClient),
        preferenceHistoryGateway: SupabasePreferenceHistoryGateway(
          supabaseClient,
        ),
      ),
    ),
  );
}

/// A debug run started with SOOL_TEST_AUTO_LOGIN=true signs in as the test
/// account from the same defines, so the simulator never needs a social
/// login. Release builds ignore the defines.
Future<void> _signInTestUser(SupabaseClient client) async {
  const enabled = String.fromEnvironment('SOOL_TEST_AUTO_LOGIN') == 'true';
  if (!kDebugMode || !enabled || client.auth.currentSession != null) return;
  try {
    await client.auth
        .signInWithPassword(
          email: const String.fromEnvironment('SOOL_TEST_EMAIL'),
          password: const String.fromEnvironment('SOOL_TEST_PASSWORD'),
        )
        .timeout(const Duration(seconds: 10));
  } catch (error) {
    debugPrint('Test auto-login failed: $error');
  }
}

/// The Play install referrer carries a web card's claim ticket into a fresh
/// install. It is handed over once; the app keeps the ticket in memory for
/// the retry on the result page.
Future<String?> _readInstallReferrerOnce() async {
  const key = 'install_referrer_consumed';
  final preferences = await SharedPreferences.getInstance();
  if (preferences.getBool(key) ?? false) return null;
  final details = await PlayInstallReferrer.installReferrer;
  await preferences.setBool(key, true);
  return details.installReferrer;
}

/// Links the phone opens in the app. A debug run started with
/// `SOOL_CLAIM_LINK=<url>` receives that link instead, as if the phone had
/// opened it, so the claim can be tried without a store install.
Stream<Uri>? _incomingLinks() {
  if (kIsWeb) return null;
  const debugLink = String.fromEnvironment('SOOL_CLAIM_LINK');
  if (kDebugMode && debugLink.isNotEmpty) {
    return Stream<Uri>.value(Uri.parse(debugLink));
  }
  return AppLinks().uriLinkStream;
}
