import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import '../features/auth/data/social_auth_service.dart';
import '../features/catalog/data/catalog_search_gateway.dart';
import '../features/catalog/data/discovery_events.dart';
import '../features/catalog/data/catalog_drink.dart';
import '../features/editorial/data/editorial_article_gateway.dart';
import '../features/editorial/data/editorial_article.dart';
import '../features/editorial/data/editorial_article_save_state.dart';
import '../features/explore/presentation/explore_screens.dart';
import '../features/home/presentation/home_screens.dart';
import '../core/sensory/sensory_question_flow.dart';
import '../features/catalog/data/suggested_drinks.dart';
import '../features/onboarding/data/sensory_questionnaire_data.dart';
import '../features/onboarding/data/onboarding_entry_draft.dart';
import '../features/onboarding/presentation/auth/app_loading_screen.dart';
import '../features/onboarding/presentation/auth/login_screen.dart';
import '../features/onboarding/presentation/auth/profile_setup_screen.dart';
import '../features/onboarding/presentation/onboarding_entry_screens.dart';
import '../features/taste_card/presentation/taste_card_screen.dart';
import '../features/taste_card/presentation/widgets/record_delete_dialog.dart';
import '../features/onboarding/presentation/sensory_questionnaire_screen.dart';
import '../features/preferences/presentation/history/preference_history_screen.dart';
import '../features/profile/data/account_completion_gateway.dart';
import '../features/profile/data/account_deletion_gateway.dart';
import '../features/profile/data/liked_cards_gateway.dart';
import '../features/notifications/data/notification_access.dart';
import '../features/notifications/data/notification_prompt_memory.dart';
import '../features/profile/data/marketing_consent_gateway.dart';
import '../features/profile/data/profile_preferences_gateway.dart';
import '../features/home/data/home_providers.dart';
import '../features/preferences/data/preference_history_providers.dart';
import '../features/profile/data/profile_summary_provider.dart';
import '../features/profile/data/support_inquiry_gateway.dart';
import '../features/profile/presentation/legal_document_link.dart';
import '../features/profile/presentation/profile_screens.dart';
import '../features/records/data/record_note_gateway.dart';
import '../features/recording/presentation/drink_search_screen.dart';
import '../features/taste_card/data/taste_card_gateway.dart';
import '../features/taste_card/data/claim_link.dart';
import '../features/taste_card/presentation/widgets/taste_card_like_button.dart';
import '../features/taste_card/presentation/widgets/taste_card_more_action.dart';
import '../features/taste_fit/data/label_text_recognizer.dart';
import '../features/taste_fit/data/label_photo_picker.dart';
import '../features/taste_fit/data/taste_fit_gateway.dart';
import '../features/taste_fit/presentation/taste_fit_detail_screen.dart';
import '../features/taste_fit/presentation/taste_fit_search_screen.dart';
import '../navigation/app_route.dart';
import '../navigation/app_router.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_screen.dart';
import '../widgets/app_dialog.dart';
import 'app_header_policy.dart';
import 'flows/account_coordinator.dart';
import 'flows/claim_coordinator.dart';
import 'flows/app_gateways.dart';
import 'flows/flow_host.dart';
import 'flows/notification_prompt_coordinator.dart';
import 'flows/onboarding_coordinator.dart';
import 'flows/record_coordinator.dart';
import 'flows/taste_card_coordinator.dart';
import 'state/sensory_session.dart';
import 'state/taste_card_flow_state.dart';
import '../widgets/app_state_view.dart';
import '../widgets/app_snack_bar.dart';
import '../core/analytics.dart';
import '../core/saved_views.dart';
import '../core/open_link.dart';

part 'app_flow_debug.dart';
part 'app_flow_pages.dart';

/// The Navigator shell. Flow logic lives in the coordinators under `flows/`;
/// this widget hosts them, maps routes to screens and handles back.
class AppFlow extends ConsumerStatefulWidget {
  const AppFlow({
    required this.initialRoute,
    this.isWeb = false,
    this.incomingLinks,
    this.installReferrer,
    this.socialAuthGateway,
    this.profilePreferencesGateway,
    this.likedCardsGateway,
    this.recordNoteGateway,
    this.supportInquiryGateway,
    this.marketingConsentGateway,
    this.notificationAccess,
    this.notificationPromptMemory,
    this.accountCompletionGateway,
    this.accountDeletionGateway,
    this.editorialArticleGateway,
    this.catalogSearchGateway,
    this.discoveryEvents,
    this.tasteCardGateway,
    this.tasteFitGateway,
    this.labelPhotoPicker,
    this.savedViews,
    this.analytics = const NoAnalytics(),
    this.sensoryQuestionnaireLoader = loadSensoryQuestionnaireData,
    super.key,
  });

  final AppRoute initialRoute;

  /// The web shows the first-record onboarding only; its result sends the
  /// visitor to the mobile app.
  final bool isWeb;
  final Stream<Uri>? incomingLinks;
  final Future<String?> Function()? installReferrer;
  final SocialAuthGateway? socialAuthGateway;
  final ProfilePreferencesGateway? profilePreferencesGateway;
  final LikedCardsGateway? likedCardsGateway;
  final RecordNoteGateway? recordNoteGateway;
  final SupportInquiryGateway? supportInquiryGateway;
  final MarketingConsentGateway? marketingConsentGateway;
  final NotificationAccess? notificationAccess;
  final NotificationPromptMemory? notificationPromptMemory;
  final AccountCompletionGateway? accountCompletionGateway;
  final AccountDeletionGateway? accountDeletionGateway;
  final EditorialArticleGateway? editorialArticleGateway;
  final CatalogSearchGateway? catalogSearchGateway;
  final DiscoveryEventGateway? discoveryEvents;
  final TasteCardGateway? tasteCardGateway;
  final TasteFitGateway? tasteFitGateway;
  final LabelPhotoPicker? labelPhotoPicker;
  final SavedViews? savedViews;
  final Analytics analytics;
  final SensoryQuestionnaireLoader sensoryQuestionnaireLoader;

  AppGateways get gateways => AppGateways(
    sensoryQuestionnaireLoader: sensoryQuestionnaireLoader,
    isWeb: isWeb,
    incomingLinks: incomingLinks,
    installReferrer: installReferrer,
    socialAuth: socialAuthGateway,
    profilePreferences: profilePreferencesGateway,
    likedCards: likedCardsGateway,
    recordNote: recordNoteGateway,
    supportInquiry: supportInquiryGateway,
    marketingConsent: marketingConsentGateway,
    notifications: notificationAccess,
    notificationPromptMemory: notificationPromptMemory,
    accountCompletion: accountCompletionGateway,
    accountDeletion: accountDeletionGateway,
    editorialArticle: editorialArticleGateway,
    catalogSearch: catalogSearchGateway,
    discoveryEvents: discoveryEvents,
    tasteCard: tasteCardGateway,
    tasteFit: tasteFitGateway,
    labelPhotoPicker: labelPhotoPicker,
    savedViews: savedViews,
    analytics: analytics,
  );

  @override
  ConsumerState<AppFlow> createState() => _AppFlowState();
}

class _AppFlowState extends ConsumerState<AppFlow> implements FlowHost {
  late final AppGateways _gateways = widget.gateways;

  /// My Page counts; reloaded only when something they count changes.
  late final ProfileSummaryNotifier _profileSummary = ref.read(
    profileSummaryProvider.notifier,
  );
  late final TasteCardCoordinator _tasteCard = TasteCardCoordinator(
    this,
    _gateways,
    onRecordSaved: _cardSaved,
  );
  final _leavingPages = LeavingPagesObserver();
  late final NotificationPromptCoordinator _notificationPrompt =
      NotificationPromptCoordinator(
        this,
        _gateways,
        pagesSettled: _leavingPages.settled,
      );
  late final OnboardingCoordinator _onboarding = OnboardingCoordinator(
    this,
    _tasteCard,
  );
  late final RecordCoordinator _record = RecordCoordinator(this, _tasteCard);
  late final ClaimCoordinator _claim = ClaimCoordinator(
    this,
    _gateways,
    _tasteCard,
  );
  late final AccountCoordinator _account = AccountCoordinator(
    this,
    _gateways,
    _onboarding,
    _record,
    _tasteCard,
    _claim,
    _profileSummary,
    onSignedOut: _forgetAccount,
    onLanded: _warmOtherTabs,
  );
  final _AppFlowDebugState _debug = _AppFlowDebugState();

  /// The question screen's SKIP, shown at the header's right end.
  final _sensorySkip = SensorySkipNotifier();
  EditorialArticle? _selectedEditorialArticle;

  /// Bookmark of the open post; the article header reads it.
  EditorialArticleSaveState? _editorialSave;

  /// The bottle the taste-fit search opened; `null` on a direct link.
  TasteFitSelection? _tasteFit;

  /// Whether the search screen being opened asks for a label photo first.
  bool _tasteFitScanOnOpen = false;

  /// The router whose route changes are watched, and the route it was on.
  AppRouter? _watchedRouter;
  AppRoute? _lastRoute;

  /// A card that is not the member's first was just saved and is on screen.
  bool _newRepeatCard = false;

  void _cardSaved() {
    _recordsChanged();
    if (_tasteCard.viewContext == TasteCardViewContext.repeatRecord) {
      _newRepeatCard = true;
    }
  }

  /// Asks about notifications when the member has just left a bottle's fit
  /// or a newly saved card.
  void _routeChanged() {
    final previous = _lastRoute;
    final current = router.currentRoute;
    _lastRoute = current;
    final ask = isNotificationPromptMoment(
      previous: previous,
      current: current,
      newRepeatCard: _newRepeatCard,
    );
    if (previous == AppRoute.onboardingResult && previous != current) {
      _newRepeatCard = false;
    }
    if (ask) unawaited(_notificationPrompt.offer());
  }

  /// A card was saved, claimed or deleted: what is drawn from the reader's
  /// cards loads again, and the old stays on screen until it arrives.
  void _recordsChanged() {
    ref.invalidate(tasteLettersProvider);
    ref.invalidate(nextDrinkGuidesProvider);
    ref.invalidate(historyLatestProvider);
    ref.invalidate(historyMonthProvider);
    _profileSummary.refresh();
  }

  /// Home or the record tab was pulled down: what [_recordsChanged] reloads
  /// is asked again, for a card saved on the web or another device. Ends
  /// when home's part has arrived; a failure shows where it always does.
  Future<void> _reloadRecords() async {
    _recordsChanged();
    try {
      await (
        ref.read(tasteLettersProvider.future),
        ref.read(nextDrinkGuidesProvider.future),
      ).wait;
    } catch (_) {
      // Each card shows its own failure.
    }
  }

  /// Home has just opened for a signed-in account. What the 취향 and 탐색
  /// tabs show first is asked for now, behind home, so each tab is there the
  /// moment it is first opened: the month of the newest record, and the
  /// published posts. A failure here is left for the tab to show and retry.
  void _warmOtherTabs() {
    if (!_gateways.isWeb) unawaited(_gateways.notifications?.resume());
    if (ref.read(preferenceHistoryGatewayProvider) != null) {
      ref.read(historyLatestProvider.future).then((newest) {
        final month = newest ?? DateTime.now();
        return ref.read(
          historyMonthProvider(DateTime(month.year, month.month)).future,
        );
      }).ignore();
    }
    _gateways.editorialArticle?.fetchPublishedArticles().ignore();
  }

  /// The account signed out: nothing of it may show to the next one.
  void _forgetAccount() {
    unawaited(_gateways.savedViews?.clear());
    _profileSummary.clear();
    ref.invalidate(tasteLettersProvider, asReload: true);
    ref.invalidate(nextDrinkGuidesProvider, asReload: true);
    ref.invalidate(historyLatestProvider, asReload: true);
    ref.invalidate(historyMonthProvider, asReload: true);
  }

  /// Whether the account has no card yet. Unknown counts read as "has
  /// cards", so a failed load never blocks the ordinary record.
  Future<bool> _isFirstRecord() async {
    var summary = ref.read(profileSummaryProvider).summary;
    if (summary == null) {
      try {
        summary = await _profileSummary.load();
      } catch (_) {
        return false;
      }
    }
    return summary?.cardCount == 0;
  }

  /// 기록하기: a member without a card walks the first-record onboarding,
  /// over the tab it was pressed on, from its drink search: the intro is for
  /// a visitor who has not decided to record yet. Every record after it is
  /// the ordinary one.
  Future<void> _startRecord() async {
    final first = await _isFirstRecord();
    if (!mounted) return;
    if (first) {
      router.push(AppRoute.onboardingSearch);
    } else {
      _record.startFlow();
    }
  }

  /// 기록하기 on a bottle already chosen; see [_startRecord].
  Future<void> _startRecordWith(DrinkSelection selection) async {
    final first = await _isFirstRecord();
    if (!mounted) return;
    if (first) {
      _onboarding.continueWithDrinkSelection(selection);
    } else {
      _record.startFlowWith(selection);
    }
  }

  /// Bumped when an opened card's like changes or its record is deleted, so
  /// 저장한 술결 카드, which stays mounted under the card, reloads.
  int _likedCardsRevision = 0;

  @override
  AppRouter get router => AppRouterScope.of(context);

  AppRoute get _route => router.currentRoute;

  @override
  void refresh(VoidCallback update) => setState(update);

  @override
  void showFeedback(String message, {bool success = false}) {
    showAppSnackBar(context, message, success: success);
  }

  /// Asks before deleting the saved card on screen; the popup stays up with
  /// a spinner while the card is deleted, then the flow leaves the card.
  Future<void> _confirmRecordDelete() async {
    final navigatorContext = router.navigatorKey.currentContext;
    if (navigatorContext == null) return;
    // Set by the first 삭제; a popup closed meanwhile leaves the delete
    // running, and its outcome is still waited for below.
    Future<bool>? deletion;
    await showAppDialog<void>(
      context: navigatorContext,
      builder: (_) => RecordDeleteDialog(
        onDelete: () async {
          await (deletion ??= _deleteShownCard());
        },
      ),
    );
    final deleted = await deletion;
    if (deleted == null || !mounted) return;
    if (!deleted) {
      showFeedback('기록을 삭제하지 못했어요. 다시 시도해 주세요.');
      return;
    }
    _recordsChanged();
    setState(() => _likedCardsRevision++);
    if (!router.pop()) router.replaceRoot(AppRoute.home);
    showFeedback('기록을 삭제했어요.', success: true);
  }

  /// Whether the card on screen was deleted.
  Future<bool> _deleteShownCard() async {
    try {
      await _tasteCard.deleteShownCard();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _seedRequiredDrinkForDebug(widget.initialRoute);
    _account.listenToSession();
    if (widget.initialRoute == AppRoute.appLoading) _account.startAppEntry();
    _claim.start();
  }

  @override
  void dispose() {
    _watchedRouter?.removeListener(_routeChanged);
    _sensorySkip.dispose();
    _editorialSave?.dispose();
    _account.dispose();
    _claim.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_watchedRouter != router) {
      _watchedRouter?.removeListener(_routeChanged);
      _watchedRouter = router..addListener(_routeChanged);
      _lastRoute = router.currentRoute;
    }
    _requestNativeDebugScreenOnce();
  }

  /// The sensory session and routes of the flow that owns [route].
  _SensoryContext? _sensoryContextFor(AppRoute route) => switch (route) {
    AppRoute.onboardingQuestions => _SensoryContext.onboarding(_onboarding),
    AppRoute.recordQuestions => _SensoryContext.record(_record),
    _ => null,
  };

  bool _canGoBackInSensoryFlow(_SensoryContext context) {
    final flow = context.session.flow;
    return flow != null && flow.current.page != SensoryPage.revisit;
  }

  bool _sensoryHandlesSystemBack() {
    final context = _sensoryContextFor(_route);
    return context != null && _canGoBackInSensoryFlow(context);
  }

  @override
  void back() {
    final sensory = _sensoryContextFor(_route);
    if (sensory != null && _canGoBackInSensoryFlow(sensory)) {
      setState(() => sensory.session.flow!.back());
      return;
    }
    router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final navigation = router;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!_sensoryHandlesSystemBack()) return false;
        back();
        return true;
      },
      child: Navigator(
        key: navigation.navigatorKey,
        observers: <NavigatorObserver>[_leavingPages],
        pages: <Page<void>>[
          for (final (depth, route) in navigation.stack.indexed)
            // The four tabs share the bottom page, so switching between
            // them is no page change: see [_TabPages].
            if (depth == 0 && _activeTabOf(route) != null)
              MaterialPage<void>(
                key: _TabPages.pageKey,
                name: route.path,
                child: _TabPages(
                  active: route,
                  buildPage: (tab) => _buildRoutePage(context, tab),
                ),
              )
            else
              MaterialPage<void>(
                key: ValueKey<AppRoute>(route),
                name: route.path,
                child: _buildRoutePage(context, route),
              ),
        ],
        onDidRemovePage: (page) {
          final key = page.key;
          if (key is ValueKey<AppRoute>) {
            navigation.didRemovePage(key.value);
          }
        },
      ),
    );
  }
}

/// Everything the sensory questionnaire pages need from the owning flow.
class _SensoryContext {
  _SensoryContext.onboarding(OnboardingCoordinator onboarding)
    : session = onboarding.state.sensory,
      resolveSelection = (() => onboarding.selectedDrink),
      questionsRoute = AppRoute.onboardingQuestions,
      submit = onboarding.submitTasteCard,
      aromaSearch = false;

  _SensoryContext.record(RecordCoordinator record)
    : session = record.state.sensory,
      resolveSelection = (() => record.state.drinkSelection!),
      questionsRoute = AppRoute.recordQuestions,
      submit = record.submitTasteCard,
      aromaSearch = true;

  final SensorySession session;
  final DrinkSelection Function() resolveSelection;
  final AppRoute questionsRoute;

  /// Only a record after the first searches the aroma dictionary.
  final bool aromaSearch;

  /// The completed questionnaire submits the record straight away; the
  /// result route it opens shows the card.
  final Future<void> Function() submit;
}

/// The tab pages, under one page of the Navigator. A tab that was opened
/// stays built behind the one on screen, so coming back finds it as it was
/// left: where it was scrolled to, which month or filter was chosen. All of
/// them go when the page does, as on sign-out.
class _TabPages extends StatefulWidget {
  const _TabPages({required this.active, required this.buildPage});

  static const pageKey = ValueKey<String>('tabs');

  final AppRoute active;
  final Widget Function(AppRoute tab) buildPage;

  @override
  State<_TabPages> createState() => _TabPagesState();
}

class _TabPagesState extends State<_TabPages> {
  /// In the order they were first opened, so each keeps its place.
  late final _opened = <AppRoute>[widget.active];

  @override
  void didUpdateWidget(covariant _TabPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_opened.contains(widget.active)) _opened.add(widget.active);
  }

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: _opened.indexOf(widget.active),
    sizing: StackFit.expand,
    children: <Widget>[
      for (final tab in _opened)
        // A tab behind the others is neither animated nor focused, and
        // its notice is no second hero when a page opens over the tabs.
        TickerMode(
          key: ValueKey<AppRoute>(tab),
          enabled: tab == widget.active,
          child: HeroMode(
            enabled: tab == widget.active,
            child: ExcludeFocus(
              excluding: tab != widget.active,
              child: widget.buildPage(tab),
            ),
          ),
        ),
    ],
  );
}
