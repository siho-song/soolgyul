import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app/app.dart';
import 'src/app/app_start.dart';
import 'src/app/asset_warmup.dart';
import 'src/config/app_config.dart';
import 'src/core/errors/error_report.dart';
import 'src/core/google_analytics.dart';
import 'src/core/saved_views.dart';
import 'src/core/secure_session_storage.dart';
import 'src/core/supabase/time_limited_client.dart';
import 'src/widgets/app_network_image.dart';
import 'src/features/app_gate/data/app_gate.dart';
import 'src/features/app_gate/presentation/app_gate_view.dart';
import 'src/features/auth/data/social_auth_service.dart';
import 'src/features/catalog/data/discovery_events.dart';
import 'src/features/catalog/data/remembered_catalog_search.dart';
import 'src/features/catalog/data/supabase_catalog_search_gateway.dart';
import 'src/features/editorial/data/supabase_editorial_article_gateway.dart';
import 'src/features/home/data/supabase_next_drink_guides_gateway.dart';
import 'src/features/home/data/supabase_taste_letters_gateway.dart';
import 'src/features/preferences/data/supabase_preference_history_gateway.dart';
import 'src/features/profile/data/supabase_profile_preferences_gateway.dart';
import 'src/features/profile/data/supabase_profile_summary.dart';
import 'src/features/profile/data/supabase_liked_cards_gateway.dart';
import 'src/features/taste_fit/data/supabase_saved_drinks_gateway.dart';
import 'src/features/profile/data/supabase_support_inquiry_gateway.dart';
import 'src/features/home_tour/data/home_tour_memory.dart';
import 'src/features/notifications/data/firebase_phone_notifications.dart';
import 'src/features/notifications/data/notification_access.dart';
import 'src/features/notifications/data/phone_notification_access.dart';
import 'src/features/notifications/data/notification_prompt_memory.dart';
import 'src/features/profile/data/marketing_consent_gateway.dart';
import 'src/features/profile/data/supabase_account_completion_gateway.dart';
import 'src/features/profile/data/account_deletion_gateway.dart';
import 'src/features/records/data/supabase_record_note_gateway.dart';
import 'src/features/records/data/supabase_record_price_gateway.dart';
import 'src/features/taste_card/data/supabase_taste_card_gateway.dart';
import 'src/features/taste_fit/data/supabase_taste_fit_gateway.dart';
import 'src/widgets/browser_safe_area.dart';

export 'src/app/app.dart';
export 'src/app/app_flow.dart';

bool get _onPhone =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<void> main() => runWithErrorReporting(
  // A debug build shows its errors on screen and in the console; only
  // release and profile builds send them, so a driven simulator does not
  // spend the collector's monthly allowance meant for members' phones.
  dsn: kDebugMode ? '' : AppConfig.sentryDsn,
  environment: AppConfig.environment,
  // The bindings start where the app runs: on the web the collector runs
  // this in a zone of its own, and Flutter refuses bindings from another.
  start: () {
    WidgetsFlutterBinding.ensureInitialized();
    enableBrowserSafeArea();
    if (kReleaseMode) ErrorWidget.builder = brokenView;
    runApp(const AppStart(start: _startApp));
  },
);

/// Everything the app needs before its first screen. A step that fails
/// leaves the member on [AppStart]'s retry, which runs this again.
Future<Widget> _startApp() async {
  AppConfig.validateSupabase();
  // Web logs in through Supabase OAuth redirects; the native client IDs are
  // only needed by the phone SDKs.
  if (!kIsWeb) AppConfig.validateSocialAuth();

  // A phone keeps downloaded photos on the device; a browser does already.
  if (!kIsWeb) {
    networkImageProvider = (url) => CachedNetworkImageProvider(url);
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    httpClient: TimeLimitedClient(),
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      // A phone keeps the session in its secure storage; a browser has none,
      // so web stays on the package default.
      localStorage: _onPhone
          ? SecureSessionStorage.forProject(AppConfig.supabaseUrl)
          : null,
      pkceAsyncStorage: _onPhone ? const SecurePkceStorage() : null,
    ),
  );

  if (_onPhone) {
    await KakaoSdk.init(
      nativeAppKey: AppConfig.kakaoNativeAppKey,
      customScheme: AppConfig.kakaoNativeAppScheme,
    );
  }

  final supabaseClient = Supabase.instance.client;
  await _signInTestUser(supabaseClient);
  // What the signed-in member last saw stays on the phone for the next
  // launch, a folder per account.
  final savedViews = SavedViewFiles(
    accountId: () => supabaseClient.auth.currentUser?.id,
  );
  final socialAuth = SocialAuthService(supabaseClient);
  final platform = kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';
  final installed = kIsWeb ? null : await _installedApp();
  return AppGateView(
    load: () => loadAppGate(supabaseClient, platform),
    installedVersion: installed?.version,
    storeAddress: switch (platform) {
      'ios' => AppConfig.appStoreUrl,
      'android' when AppConfig.playStoreUrl.isNotEmpty =>
        AppConfig.playStoreUrl,
      'android' when installed != null =>
        'https://play.google.com/store/apps/details?id=${installed.packageName}',
      _ => null,
    },
    child: _app(supabaseClient, savedViews, socialAuth),
  );
}

/// The installed version; null when the phone will not say, which only
/// means no version of it is ever called too old.
Future<PackageInfo?> _installedApp() async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (_) {
    return null;
  }
}

Widget _app(
  SupabaseClient supabaseClient,
  SavedViewFiles savedViews,
  SocialAuthService socialAuth,
) {
  final app = App(
    incomingLinks: _incomingLinks(),
    installReferrer: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? _readInstallReferrerOnce
        : null,
    socialAuthGateway: socialAuth,
    accountDeletionGateway: SupabaseAccountDeletionGateway(
      supabaseClient,
      loadProviderProof: socialAuth.prepareDeletionProof,
    ),
    profileSummaryLoader: SupabaseProfileSummary(supabaseClient).load,
    likedCardsGateway: SupabaseLikedCardsGateway(supabaseClient),
    savedDrinksGateway: SupabaseSavedDrinksGateway(supabaseClient),
    recordNoteGateway: SupabaseRecordNoteGateway(supabaseClient),
    recordPriceGateway: SupabaseRecordPriceGateway(supabaseClient),
    supportInquiryGateway: SupabaseSupportInquiryGateway(supabaseClient),
    marketingConsentGateway: SupabaseMarketingConsentGateway(supabaseClient),
    notificationAccess: _notifications(supabaseClient),
    notificationPromptMemory: DeviceNotificationPromptMemory(
      accountId: () => supabaseClient.auth.currentUser?.id,
    ),
    homeTourMemory: DeviceHomeTourMemory(
      accountId: () => supabaseClient.auth.currentUser?.id,
    ),
    profilePreferencesGateway: SupabaseProfilePreferencesGateway(
      supabaseClient,
      saved: savedViews,
    ),
    accountCompletionGateway: SupabaseAccountCompletionGateway(supabaseClient),
    editorialArticleGateway: SupabaseEditorialArticleGateway(
      supabaseClient,
      saved: savedViews,
    ),
    catalogSearchGateway: RememberedCatalogSearch(
      SupabaseCatalogSearchGateway(supabaseClient),
    ),
    discoveryEvents: SupabaseDiscoveryEventGateway(supabaseClient),
    analytics: GoogleAnalytics.start(counted: AppConfig.countsUsage),
    tasteCardGateway: SupabaseTasteCardGateway(
      supabaseClient,
      saved: savedViews,
    ),
    tasteFitGateway: SupabaseTasteFitGateway(supabaseClient),
    tasteLettersGateway: SupabaseTasteLettersGateway(
      supabaseClient,
      saved: savedViews,
    ),
    nextDrinkGuidesGateway: SupabaseNextDrinkGuidesGateway(
      supabaseClient,
      saved: savedViews,
    ),
    preferenceHistoryGateway: SupabasePreferenceHistoryGateway(
      supabaseClient,
      saved: savedViews,
    ),
    savedViews: savedViews,
  );
  // Warming on the web downloads every bundled picture (some 10 MB) to
  // show the few its onboarding draws; those load as they are shown.
  return kIsWeb ? app : AssetWarmup(child: app);
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

/// Notifications reach a phone through Firebase; a browser has none. A debug
/// build started with `SOOL_NOTIFICATIONS=pretend` (or `blocked`) pretends
/// them instead, to look at the question and the settings row without
/// asking the phone.
NotificationAccess? _notifications(SupabaseClient client) {
  if (kIsWeb) return null;
  const mode = String.fromEnvironment('SOOL_NOTIFICATIONS');
  if (kDebugMode && mode.isNotEmpty) {
    return PretendNotificationAccess(
      status: mode == 'blocked'
          ? NotificationStatus.blocked
          : NotificationStatus.off,
    );
  }
  return PhoneNotificationAccess(
    phone: FirebasePhoneNotifications(),
    registry: SupabasePushDeviceRegistry(client),
    accountId: () => client.auth.currentUser?.id,
  );
}
