import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import '../design/design_system_preview_screen.dart';
import '../features/auth/data/social_auth_service.dart';
import '../features/catalog/data/adaptive_onboarding_test_catalog.dart';
import '../features/catalog/data/catalog_search_gateway.dart';
import '../features/catalog/data/catalog_drink.dart';
import '../features/editorial/data/editorial_article_gateway.dart';
import '../features/editorial/data/editorial_article.dart';
import '../features/editorial/data/editorial_article_save_state.dart';
import '../features/explore/presentation/explore_screens.dart';
import '../features/home/presentation/home_screens.dart';
import '../core/sensory/sensory_question_flow.dart';
import '../features/onboarding/data/onboarding_suggested_drinks.dart';
import '../features/onboarding/data/sensory_questionnaire_data.dart';
import '../features/onboarding/data/onboarding_entry_draft.dart';
import '../features/onboarding/presentation/auth/app_loading_screen.dart';
import '../features/onboarding/presentation/auth/login_screen.dart';
import '../features/onboarding/presentation/auth/profile_setup_screen.dart';
import '../features/onboarding/presentation/onboarding_entry_screens.dart';
import '../features/onboarding/presentation/onboarding_result_screen.dart';
import '../features/onboarding/presentation/sensory_questionnaire_screen.dart';
import '../features/taste_card/data/taste_card_snapshot_view_data.dart';
import '../features/preferences/presentation/history/preference_history_screen.dart';
import '../features/profile/data/account_completion_gateway.dart';
import '../features/profile/data/account_deletion_gateway.dart';
import '../features/profile/data/liked_cards_gateway.dart';
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
import 'app_header_policy.dart';
import 'flows/account_coordinator.dart';
import 'flows/claim_coordinator.dart';
import 'flows/app_gateways.dart';
import 'flows/flow_host.dart';
import 'flows/onboarding_coordinator.dart';
import 'flows/record_coordinator.dart';
import 'flows/taste_card_coordinator.dart';
import 'state/sensory_session.dart';
import 'state/taste_card_flow_state.dart';

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
    this.accountCompletionGateway,
    this.accountDeletionGateway,
    this.editorialArticleGateway,
    this.catalogSearchGateway,
    this.tasteCardGateway,
    this.tasteFitGateway,
    this.labelPhotoPicker,
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
  final AccountCompletionGateway? accountCompletionGateway;
  final AccountDeletionGateway? accountDeletionGateway;
  final EditorialArticleGateway? editorialArticleGateway;
  final CatalogSearchGateway? catalogSearchGateway;
  final TasteCardGateway? tasteCardGateway;
  final TasteFitGateway? tasteFitGateway;
  final LabelPhotoPicker? labelPhotoPicker;
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
    accountCompletion: accountCompletionGateway,
    accountDeletion: accountDeletionGateway,
    editorialArticle: editorialArticleGateway,
    catalogSearch: catalogSearchGateway,
    tasteCard: tasteCardGateway,
    tasteFit: tasteFitGateway,
    labelPhotoPicker: labelPhotoPicker,
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
    onRecordSaved: _recordsChanged,
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

  /// A card was saved, claimed or deleted: what is drawn from the reader's
  /// cards loads again, and the old stays on screen until it arrives.
  void _recordsChanged() {
    ref.invalidate(tasteLettersProvider);
    ref.invalidate(nextDrinkGuidesProvider);
    ref.invalidate(historyLatestProvider);
    ref.invalidate(historyMonthProvider);
    _profileSummary.refresh();
  }

  /// The account signed out: nothing of it may show to the next one.
  void _forgetAccount() {
    _profileSummary.clear();
    ref.invalidate(tasteLettersProvider, asReload: true);
    ref.invalidate(nextDrinkGuidesProvider, asReload: true);
    ref.invalidate(historyLatestProvider, asReload: true);
    ref.invalidate(historyMonthProvider, asReload: true);
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
  void showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Asks before deleting the saved card on screen, then leaves the card.
  Future<void> _confirmRecordDelete() async {
    final navigatorContext = router.navigatorKey.currentContext;
    if (navigatorContext == null) return;
    final confirmed = await showDialog<bool>(
      context: navigatorContext,
      builder: (dialogContext) => AlertDialog(
        content: const Text('저장된 술결 기록을 삭제하시겠습니까?'),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('record-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('아니오'),
          ),
          TextButton(
            key: const ValueKey<String>('record-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('예'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _tasteCard.deleteShownCard();
    } catch (_) {
      if (mounted) showFeedback('기록을 삭제하지 못했어요. 다시 시도해주세요.');
      return;
    }
    if (!mounted) return;
    _recordsChanged();
    setState(() => _likedCardsRevision++);
    if (!router.pop()) router.replaceRoot(AppRoute.home);
    showFeedback('기록을 삭제했어요.');
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
    _sensorySkip.dispose();
    _editorialSave?.dispose();
    _account.dispose();
    _claim.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    if (_debug.reviewActive) {
      _returnToDesignLab();
      return;
    }
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
        transitionDelegate: _TabSwitchTransitionDelegate(
          isTabRoot: (route) => _activeTabOf(route) != null,
        ),
        pages: <Page<void>>[
          for (final route in navigation.stack)
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

/// Switching bottom tabs swaps one tab page for another without the page
/// transition; every other change keeps the default animation.
class _TabSwitchTransitionDelegate extends TransitionDelegate<void> {
  const _TabSwitchTransitionDelegate({required this.isTabRoot});

  final bool Function(AppRoute route) isTabRoot;

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord>
    locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>>
    pageRouteToPagelessRoutes,
  }) {
    if (!_isTabSwitch(newPageRouteHistory, locationToExitingPageRoute)) {
      return const DefaultTransitionDelegate<void>().resolve(
        newPageRouteHistory: newPageRouteHistory,
        locationToExitingPageRoute: locationToExitingPageRoute,
        pageRouteToPagelessRoutes: pageRouteToPagelessRoutes,
      );
    }
    final results = <RouteTransitionRecord>[];
    void removeExiting(RouteTransitionRecord? location) {
      final exiting = locationToExitingPageRoute[location];
      if (exiting == null) return;
      if (exiting.isWaitingForExitingDecision) {
        exiting.markForComplete(exiting.route.currentResult);
        for (final pageless
            in pageRouteToPagelessRoutes[exiting] ??
                const <RouteTransitionRecord>[]) {
          if (pageless.isWaitingForExitingDecision) {
            pageless.markForComplete(pageless.route.currentResult);
          }
        }
      }
      results.add(exiting);
      removeExiting(exiting);
    }

    removeExiting(null);
    final entering = newPageRouteHistory.single;
    entering.markForAdd();
    results.add(entering);
    removeExiting(entering);
    return results;
  }

  bool _isTabSwitch(
    List<RouteTransitionRecord> newPageRouteHistory,
    Map<RouteTransitionRecord?, RouteTransitionRecord>
    locationToExitingPageRoute,
  ) {
    if (newPageRouteHistory.length != 1 ||
        !newPageRouteHistory.single.isWaitingForEnteringDecision ||
        locationToExitingPageRoute.isEmpty) {
      return false;
    }
    return <RouteTransitionRecord>[
      newPageRouteHistory.single,
      ...locationToExitingPageRoute.values,
    ].every(_isTabRecord);
  }

  bool _isTabRecord(RouteTransitionRecord record) {
    final settings = record.route.settings;
    final key = settings is Page<void> ? settings.key : null;
    return key is ValueKey<AppRoute> && isTabRoot(key.value);
  }
}
