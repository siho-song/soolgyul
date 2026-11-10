import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/error_report.dart';
import '../design/app_theme.dart';
import '../features/auth/data/social_auth_service.dart';
import '../features/catalog/data/catalog_search_gateway.dart';
import '../features/catalog/data/discovery_events.dart';
import '../features/editorial/data/editorial_article_gateway.dart';
import '../features/home/data/home_providers.dart';
import '../features/home/data/next_drink_guides.dart';
import '../features/preferences/data/preference_history_content.dart';
import '../features/preferences/data/preference_history_providers.dart';
import '../features/home/data/taste_letters.dart';
import '../features/onboarding/data/sensory_questionnaire_data.dart';
import '../features/profile/data/profile_preferences_gateway.dart';
import '../features/profile/data/profile_summary.dart';
import '../features/profile/data/profile_summary_provider.dart';
import '../features/profile/data/liked_cards_gateway.dart';
import '../features/records/data/record_note_gateway.dart';
import '../features/profile/data/support_inquiry_gateway.dart';
import '../features/profile/data/marketing_consent_gateway.dart';
import '../features/profile/data/account_completion_gateway.dart';
import '../features/profile/data/account_deletion_gateway.dart';
import '../features/taste_card/data/taste_card_gateway.dart';
import '../features/taste_fit/data/label_photo_picker.dart';
import '../features/taste_fit/data/taste_fit_gateway.dart';
import '../navigation/app_route.dart';
import '../navigation/app_router.dart';
import 'app_flow.dart';
import '../core/saved_views.dart';

const _designQa = bool.fromEnvironment('SOOL_DESIGN_QA');

class App extends StatefulWidget {
  const App({
    this.socialAuthGateway,
    this.profilePreferencesGateway,
    this.profileSummaryLoader,
    this.likedCardsGateway,
    this.recordNoteGateway,
    this.supportInquiryGateway,
    this.marketingConsentGateway,
    this.accountCompletionGateway,
    this.accountDeletionGateway,
    this.editorialArticleGateway,
    this.catalogSearchGateway,
    this.discoveryEvents,
    this.tasteCardGateway,
    this.tasteFitGateway,
    this.tasteLettersGateway,
    this.labelPhotoPicker,
    this.savedViews,
    this.nextDrinkGuidesGateway,
    this.preferenceHistoryGateway,
    this.sensoryQuestionnaireLoader = loadSensoryQuestionnaireData,
    this.isWeb = kIsWeb && !_designQa,
    this.incomingLinks,
    this.installReferrer,
    super.key,
  });

  /// The web serves onboarding only and hands off to the mobile app. A
  /// design QA run (SOOL_DESIGN_QA) serves every screen so they can be
  /// reviewed in a browser.
  final bool isWeb;

  /// Links opened in the app and the Play install referrer; both carry a
  /// web card's claim ticket. The web has neither.
  final Stream<Uri>? incomingLinks;
  final Future<String?> Function()? installReferrer;

  final SocialAuthGateway? socialAuthGateway;
  final ProfilePreferencesGateway? profilePreferencesGateway;
  final ProfileSummaryLoader? profileSummaryLoader;
  final LikedCardsGateway? likedCardsGateway;
  final RecordNoteGateway? recordNoteGateway;
  final SupportInquiryGateway? supportInquiryGateway;
  final MarketingConsentGateway? marketingConsentGateway;
  final AccountCompletionGateway? accountCompletionGateway;
  final AccountDeletionGateway? accountDeletionGateway;
  final EditorialArticleGateway? editorialArticleGateway;
  final CatalogSearchGateway? catalogSearchGateway;
  final DiscoveryEventGateway? discoveryEvents;
  final TasteCardGateway? tasteCardGateway;
  final TasteFitGateway? tasteFitGateway;
  final TasteLettersGateway? tasteLettersGateway;
  final LabelPhotoPicker? labelPhotoPicker;
  final SavedViews? savedViews;
  final NextDrinkGuidesGateway? nextDrinkGuidesGateway;
  final PreferenceHistoryGateway? preferenceHistoryGateway;
  final SensoryQuestionnaireLoader sensoryQuestionnaireLoader;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AppRoute _initialRoute;
  late final AppRouter _router;

  @override
  void initState() {
    super.initState();
    const nativeRequested = String.fromEnvironment('SOOL_SCREEN');
    final requestedRoute = nativeRequested.isEmpty
        ? AppRoute.fromUri(Uri.base)
        : AppRoute.fromLegacyName(nativeRequested);
    final entryRoute = nativeRequested.isNotEmpty && !kDebugMode
        ? requestedRoute.safeDirectEntryRoute
        : requestedRoute;
    // The app always starts with loading, then login or home; only a
    // requested debug screen opens elsewhere.
    _initialRoute = widget.isWeb
        ? entryRoute.webRoute
        : nativeRequested.isEmpty
        ? AppRoute.appLoading
        : entryRoute;
    _router = AppRouter(
      initialRoute: _initialRoute,
      redirect: widget.isWeb ? (route) => route.webRoute : null,
      child: AppFlow(
        initialRoute: _initialRoute,
        isWeb: widget.isWeb,
        incomingLinks: widget.incomingLinks,
        installReferrer: widget.installReferrer,
        socialAuthGateway: widget.socialAuthGateway,
        profilePreferencesGateway: widget.profilePreferencesGateway,
        likedCardsGateway: widget.likedCardsGateway,
        recordNoteGateway: widget.recordNoteGateway,
        supportInquiryGateway: widget.supportInquiryGateway,
        marketingConsentGateway: widget.marketingConsentGateway,
        accountCompletionGateway: widget.accountCompletionGateway,
        accountDeletionGateway: widget.accountDeletionGateway,
        editorialArticleGateway: widget.editorialArticleGateway,
        catalogSearchGateway: widget.catalogSearchGateway,
        discoveryEvents: widget.discoveryEvents,
        tasteCardGateway: widget.tasteCardGateway,
        tasteFitGateway: widget.tasteFitGateway,
        labelPhotoPicker: widget.labelPhotoPicker,
        savedViews: widget.savedViews,
        sensoryQuestionnaireLoader: widget.sensoryQuestionnaireLoader,
      ),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The app's shared state; what it reads from the server comes in through
    // this widget, so tests and design review run on their own gateways.
    return ProviderScope(
      // A failed read shows its message and a retry; nothing retries alone.
      retry: (_, _) => null,
      observers: const [ErrorReportingObserver()],
      overrides: [
        profileSummaryLoaderProvider.overrideWithValue(
          widget.profileSummaryLoader,
        ),
        tasteLettersGatewayProvider.overrideWithValue(
          widget.tasteLettersGateway,
        ),
        nextDrinkGuidesGatewayProvider.overrideWithValue(
          widget.nextDrinkGuidesGateway,
        ),
        preferenceHistoryGatewayProvider.overrideWithValue(
          widget.preferenceHistoryGateway,
        ),
      ],
      child: MaterialApp.router(
        title: '술결',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ko'),
        supportedLocales: const <Locale>[Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        scrollBehavior: const AppScrollBehavior(),
        routerDelegate: _router,
        routeInformationParser: AppRouteInformationParser(
          fallback: _initialRoute,
        ),
      ),
    );
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    ...super.dragDevices,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}
