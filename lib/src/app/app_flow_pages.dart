part of 'app_flow.dart';

/// Route-to-screen wiring for [AppFlow]. Screens receive coordinator state
/// and callbacks; no flow logic lives here.
extension _AppFlowPages on _AppFlowState {
  Widget _buildRoutePage(BuildContext context, AppRoute route) {
    final currentScreen = _buildCurrentScreen(route);
    if (!_debug.reviewActive || route != _route) {
      return currentScreen;
    }

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _returnToDesignLab();
        }
      },
      child: DesignReviewNavigationOverlay(
        onBack: _returnToDesignLab,
        child: currentScreen,
      ),
    );
  }

  /// Every route renders inside one [AppScreen]: the header comes from
  /// [AppHeaderPolicy], the bottom navigation from [_activeTabOf] and the
  /// body from [_screenBody].
  Widget _buildCurrentScreen(AppRoute route) {
    // Release builds never show the design lab; it falls back to welcome.
    final screenRoute = route == AppRoute.designLab && !kDebugMode
        ? AppRoute.onboardingWelcome
        : route;
    final activeTab = _activeTabOf(screenRoute);
    return _appScreen(
      route: screenRoute,
      bottomNavigationBar: activeTab == null
          ? null
          : _bottomNavigation(activeTab),
      child: _screenBody(screenRoute),
    );
  }

  /// The tab highlighted in the bottom navigation, or `null` for routes
  /// shown without it.
  AppTab? _activeTabOf(AppRoute route) => switch (route) {
    AppRoute.home => AppTab.home,
    AppRoute.preference => AppTab.preference,
    AppRoute.explore => AppTab.explore,
    AppRoute.profile => AppTab.profile,
    _ => null,
  };

  /// The body of each route. One exhaustive switch, grouped by section, so
  /// a new route without a screen fails to compile.
  Widget _screenBody(AppRoute route) => switch (route) {
    // App entry
    AppRoute.appLoading => const AppLoadingScreen(),
    AppRoute.appLogin => OnboardingLoginScreen(onLogin: _account.signIn),
    // Onboarding
    AppRoute.onboardingWelcome => _welcomeScreen(),
    AppRoute.onboardingSearch => _onboardingSearchScreen(),
    AppRoute.onboardingQuestions => _buildSensoryQuestionnaire(
      _SensoryContext.onboarding(_onboarding),
    ),
    AppRoute.onboardingResult => _buildTasteCardResult(),
    AppRoute.profileSetup => ProfileSetupScreen(
      profileDraft: _onboarding.state.profileSetupDraft,
      onProfileChanged: _account.updateProfileSetup,
      accountDraft: _onboarding.state.accountCompletionDraft,
      onAccountChanged: _account.updateAccountCompletion,
      onComplete: () => unawaited(_account.completeProfileSetup()),
      onOpenTerms: () => openLegalDocument(context, LegalDocument.terms),
      onOpenPrivacy: () => openLegalDocument(context, LegalDocument.privacy),
      submitting: _account.profileSetupSaving,
    ),
    // Home
    AppRoute.home => HomeScreen(
      key: ValueKey<int>(_recordsRevision),
      onOpenSoolgyulLetters: () => router.push(AppRoute.soolgyulLetters),
      onOpenCard: (resultId) => unawaited(_tasteCard.open(resultId)),
      onOpenTasteFit: () => _openTasteFitSearch(scanLabel: false),
      // Label reading is on-device; the web has no recognizer.
      onScanLabel: kIsWeb ? null : () => _openTasteFitSearch(scanLabel: true),
      tasteLettersGateway: _gateways.tasteLetters,
      nextDrinkGuidesGateway: _gateways.nextDrinkGuides,
    ),
    AppRoute.tasteFitSearch => TasteFitSearchScreen(
      catalogSearchGateway: _gateways.catalogSearch,
      tasteFitGateway: _gateways.tasteFit,
      labelTextRecognizer: kIsWeb ? null : const PlatformLabelTextRecognizer(),
      pickLabelPhoto: _gateways.labelPhotoPicker,
      scanLabelOnOpen: _tasteFitScanOnOpen,
      suggestedDrinkNames: onboardingSuggestedDrinkNames,
      onSelect: _openTasteFitDetail,
    ),
    AppRoute.tasteFitDetail => switch (_tasteFit) {
      final selection? => TasteFitDetailScreen(
        selection: selection,
        onRecord: () =>
            _record.startFlowWith(DrinkSelection.catalogMatch(selection.drink)),
      ),
      null => const Center(
        child: Text('검색에서 술을 골라주세요.', style: AppTextStyles.modalBody),
      ),
    },
    AppRoute.soolgyulLetters => SoolgyulLettersDetailScreen(
      gateway: _gateways.tasteLetters,
      onOpenCard: (resultId) => unawaited(_tasteCard.open(resultId)),
    ),
    // Preference
    AppRoute.preference => PreferenceHistoryScreen(
      key: ValueKey<int>(_recordsRevision),
      gateway: _gateways.preferenceHistory,
      onOpenCard: (resultId) => unawaited(_tasteCard.open(resultId)),
    ),
    // Explore
    AppRoute.explore => ExploreScreen(
      gateway: _gateways.editorialArticle,
      onOpenArticle: _openEditorialArticle,
    ),
    AppRoute.editorialArticle => switch ((
      _selectedEditorialArticle,
      _gateways.editorialArticle,
    )) {
      (final article?, final gateway?) => EditorialArticleDetailScreen(
        article: article,
        gateway: gateway,
        onOpenArticle: _openEditorialArticle,
      ),
      _ => const Center(
        child: Text('탐색에서 읽을 글을 골라주세요.', style: AppTextStyles.modalBody),
      ),
    },
    // Profile
    AppRoute.profile => ProfileScreen(
      nickname: _account.nickname,
      interests: _account.interests,
      onNavigate: _openProfileDestination,
      onSaveNickname: _account.saveNickname,
      onSaveInterests: _account.saveProfileInterests,
    ),
    AppRoute.savedCards => SavedCardsScreen(
      gateway: _gateways.likedCards,
      onUnliked: _profileSummary.refresh,
    ),
    AppRoute.savedArticles => SavedArticlesScreen(
      gateway: _gateways.editorialArticle,
      onOpenArticle: _openEditorialArticle,
    ),
    AppRoute.supportCenter => SupportCenterScreen(
      onInquiry: () => router.push(AppRoute.supportInquiry),
    ),
    AppRoute.supportInquiry => SupportInquiryScreen(
      gateway: _gateways.supportInquiry,
    ),
    AppRoute.policy => PolicyScreen(
      onSignOut: _account.signOut,
      onRequestAccountDeletion: _gateways.accountDeletion == null
          ? null
          : _account.requestAccountDeletion,
      marketingConsentGateway: _gateways.marketingConsent,
      isActive: _route == AppRoute.policy,
    ),
    // Recording
    AppRoute.recordEntry || AppRoute.recordSearch => _drinkSearchScreen(
      initialDrinkName: _record.state.drinkSelection?.displayName,
      onDrinkSelection: _record.continueWithDrinkSelection,
      // Label reading is on-device; the web has no recognizer.
      labelTextRecognizer: kIsWeb ? null : const PlatformLabelTextRecognizer(),
    ),
    AppRoute.recordQuestions => _buildSensoryQuestionnaire(
      _SensoryContext.record(_record),
    ),
    // Debug
    // The kDebugMode check here, not only above, lets release builds drop
    // the design lab code entirely.
    AppRoute.designLab =>
      kDebugMode
          ? DesignSystemPreviewScreen(
              initialView: _debug.selectedView,
              onViewChanged: (value) => _debug.selectedView = value,
              onOpenScreen: _openDesignReviewScreen,
            )
          : _welcomeScreen(),
  };

  /// Local search list used only when no catalog gateway is wired.
  List<CatalogDrink>? get _localCatalogDrinks => _gateways.catalogSearch == null
      ? AdaptiveOnboardingTestCatalog.drinks
      : null;

  Widget _welcomeScreen() {
    // Look the suggested drinks up while the visitor reads the welcome page
    // so the search page shows them as soon as it opens.
    final catalogSearch = _gateways.catalogSearch;
    if (catalogSearch != null) {
      unawaited(
        SuggestedDrinks.load(catalogSearch, onboardingSuggestedDrinkNames),
      );
    }
    return OnboardingWelcomeScreen(
      onStart: () => router.push(AppRoute.onboardingSearch),
    );
  }

  Widget _onboardingSearchScreen() => _drinkSearchScreen(
    initialDrinkName: _onboarding.state.entryDraft.drinkName,
    onDrinkSelection: _onboarding.continueWithDrinkSelection,
  );

  /// The first record and every record after it open the same search page.
  Widget _drinkSearchScreen({
    required String? initialDrinkName,
    required ValueChanged<DrinkSelection> onDrinkSelection,
    LabelTextRecognizer? labelTextRecognizer,
  }) => RecordDrinkSearchScreen(
    initialDrinkName: initialDrinkName,
    labelTextRecognizer: labelTextRecognizer,
    pickLabelPhoto: _gateways.labelPhotoPicker,
    catalogDrinks: _localCatalogDrinks,
    catalogSearchGateway: _gateways.catalogSearch,
    title: '최근에 마신 술은 무엇인가요?',
    description: '정확한 이름이 아니어도 괜찮아요',
    searchHintText: '술 이름이나 브랜드를 검색해 보세요',
    onDrinkSelection: onDrinkSelection,
    standaloneOnly: true,
    suggestedDrinkNames: onboardingSuggestedDrinkNames,
  );

  Widget _buildTasteCardResult() {
    if (_gateways.tasteCard == null) {
      // Without a gateway (tests, design review) the approved fixture card
      // stands in for a server result.
      return OnboardingResultScreen(
        viewData: TasteCardSnapshotViewData.designFixture,
        onSave: () {},
        onOpenApp: widget.isWeb ? _openClaimLink : null,
      );
    }
    final state = _tasteCard.state;
    final result = state.result;
    if (state.phase == TasteCardFlowPhase.finalResult && result != null) {
      return OnboardingResultScreen(
        viewData: result.viewData,
        // A card opened again is saved already; the header leads back.
        onSave: _tasteCard.showsSavedCard ? null : _tasteCard.save,
        onOpenApp: widget.isWeb ? _openClaimLink : null,
        isSaved: result.isSaved,
      );
    }
    final loadState = switch (state.phase) {
      TasteCardFlowPhase.submitting => OnboardingResultLoadState.loading,
      TasteCardFlowPhase.retryable => OnboardingResultLoadState.retryable,
      TasteCardFlowPhase.idle ||
      TasteCardFlowPhase.failure ||
      TasteCardFlowPhase.finalResult => OnboardingResultLoadState.failure,
    };
    return OnboardingResultStatusScreen(
      state: loadState,
      onRetry: () => unawaited(_tasteCard.retry()),
      savedCard: _tasteCard.showsSavedCard,
    );
  }

  /// 좋아요 and 더보기 at the right end of a saved record's card header. The
  /// menu holds the note, which belongs to the app's records made now or
  /// opened again, and deletion, for a card opened again from a list. The
  /// first onboarding card has neither, so no menu.
  List<Widget> _resultHeaderActions() {
    final state = _tasteCard.state;
    final result = state.result;
    final recordId = result?.recordId;
    if (state.phase != TasteCardFlowPhase.finalResult ||
        result == null ||
        recordId == null ||
        !result.isSaved) {
      return const <Widget>[];
    }
    final likedCards = _gateways.likedCards;
    final recordNote =
        _tasteCard.viewContext == TasteCardViewContext.repeatRecord
        ? _gateways.recordNote
        : null;
    final onDelete = _tasteCard.showsSavedCard
        ? () => unawaited(_confirmRecordDelete())
        : null;
    return <Widget>[
      if (likedCards != null)
        TasteCardLikeButton(
          cardId: recordId,
          gateway: likedCards,
          isActive: _route == AppRoute.onboardingResult,
          onChanged: _profileSummary.refresh,
        ),
      if (recordNote != null || onDelete != null)
        TasteCardMoreAction(
          key: ValueKey<String>('record-more:$recordId'),
          recordId: recordId,
          noteGateway: recordNote,
          // The 취향 tab's card shows the note too.
          onNoteSaved: () => refresh(() => _recordsRevision++),
          onDelete: onDelete,
        ),
    ];
  }

  /// The web's result opens the card's claim link on the intro site: a
  /// phone with the app opens it in the app, one without it reaches the
  /// store with the ticket. Without a ticket (the design fixture) the link
  /// has nothing to carry and the store page opens as it is.
  void _openClaimLink() {
    final ticket = _tasteCard.state.result?.pendingConversion;
    final link = ticket == null
        ? Uri.parse(
            AppConfig.claimLinkBaseUrl,
          ).replace(path: TasteCardClaimLink.path)
        : TasteCardClaimLink.build(AppConfig.claimLinkBaseUrl, ticket);
    unawaited(launchUrl(link, webOnlyWindowName: '_self'));
  }

  Widget _buildSensoryQuestionnaire(_SensoryContext sensory) {
    final session = sensory.session;
    final existing = session.data;
    if (existing != null) {
      return _buildLoadedSensoryQuestionnaire(existing, sensory);
    }
    final selection = sensory.resolveSelection();
    final pending = session.load ??= Future<SensoryQuestionnaireData>.sync(
      () => _gateways.sensoryQuestionnaireLoader(selection),
    );
    return FutureBuilder<SensoryQuestionnaireData>(
      future: pending,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenX),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('질문을 불러오지 못했어요. 다시 시도해주세요.'),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    key: const ValueKey('sensory-load-retry'),
                    onPressed: () => refresh(() => session.load = null),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(semanticsLabel: '질문을 불러오는 중이에요'),
          );
        }
        return _buildLoadedSensoryQuestionnaire(snapshot.requireData, sensory);
      },
    );
  }

  Widget _buildLoadedSensoryQuestionnaire(
    SensoryQuestionnaireData data,
    _SensoryContext sensory,
  ) {
    final session = sensory.session;
    var flow = session.flow;
    if (flow == null) {
      flow = data.registry.createFlow(data.asked);
      session.data = data;
      session.flow = flow;
    }
    if (_route == sensory.questionsRoute &&
        flow.current.page == SensoryPage.complete) {
      // Browser history may return without invoking the in-app back action.
      flow.back();
    }
    return PopScope<Object?>(
      canPop: !_canGoBackInSensoryFlow(sensory),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: SensoryQuestionnaireScreen(
        flow: flow,
        registry: data.registry,
        aromaMenu: data.aromaMenu,
        aromaEngine: sensory.aromaSearch ? data.aromaEngine : null,
        skip: _sensorySkip,
        onChanged: () => _tasteCard.noteSensoryAnswersChanged(session),
        onComplete: () => unawaited(sensory.submit()),
      ),
    );
  }

  Widget _appScreen({
    required AppRoute route,
    required Widget child,
    Widget? bottomNavigationBar,
  }) {
    final isSupportPage =
        route == AppRoute.supportCenter || route == AppRoute.supportInquiry;
    return AppScreen(
      appBar: AppHeaderPolicy.build(
        route: route,
        onBack: back,
        onEditorialSave: _toggleEditorialSave,
        onEditorialShare: () => showFeedback('공유 기능을 준비 중이에요.'),
        editorialSave: route == AppRoute.editorialArticle
            ? _editorialSave
            : null,
        onEditorialInstagram: switch (_selectedEditorialArticle?.instagramUrl) {
          final url? when route == AppRoute.editorialArticle => () => unawaited(
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
          _ => null,
        },
        sensorySkip: _sensorySkip,
        resultActions: route == AppRoute.onboardingResult
            ? _resultHeaderActions()
            : const <Widget>[],
        resultShowsSavedCard: _tasteCard.showsSavedCard,
      ),
      pageDescription: route.pageDescription,
      pageDescriptionTextAlign: isSupportPage
          ? TextAlign.start
          : TextAlign.center,
      pageDescriptionStyle: isSupportPage
          ? AppTextStyles.supportPageDescription
          : null,
      extendBodyIntoTopSafeArea: route == AppRoute.profile,
      bottomNavigationBar: bottomNavigationBar,
      child: child,
    );
  }

  Widget _bottomNavigation(AppTab activeTab) {
    return AppBottomNav(
      activeTab: activeTab,
      onTab: _handleBottomTab,
      onRecord: (_) => _record.startFlow(),
      recordIntent: AppRecordIntent.startFlow,
    );
  }

  void _handleBottomTab(AppTab tab) {
    router.replaceRoot(switch (tab) {
      AppTab.home => AppRoute.home,
      AppTab.preference => AppRoute.preference,
      AppTab.record => AppRoute.recordEntry,
      AppTab.explore => AppRoute.explore,
      AppTab.profile => AppRoute.profile,
    });
  }

  void _openTasteFitSearch({required bool scanLabel}) {
    _tasteFitScanOnOpen = scanLabel;
    router.push(AppRoute.tasteFitSearch);
  }

  void _openTasteFitDetail(TasteFitSelection selection) {
    refresh(() => _tasteFit = selection);
    router.push(AppRoute.tasteFitDetail);
  }

  void _openEditorialArticle(EditorialArticle article) {
    final gateway = _gateways.editorialArticle;
    refresh(() {
      _selectedEditorialArticle = article;
      _editorialSave?.dispose();
      _editorialSave = gateway == null
          ? null
          : EditorialArticleSaveState(article: article, gateway: gateway);
    });
    router.push(AppRoute.editorialArticle);
  }

  Future<void> _toggleEditorialSave(EditorialArticleSaveState save) async {
    if (await save.toggle()) {
      _profileSummary.refresh();
    } else if (mounted) {
      showFeedback('로그인 후 게시글을 저장할 수 있어요.');
    }
  }

  void _openProfileDestination(ProfileDestination destination) {
    if (destination == ProfileDestination.notice) {
      unawaited(openLegalDocument(context, LegalDocument.notice));
      return;
    }
    router.push(switch (destination) {
      ProfileDestination.savedCards => AppRoute.savedCards,
      ProfileDestination.savedArticles => AppRoute.savedArticles,
      ProfileDestination.supportCenter => AppRoute.supportCenter,
      ProfileDestination.policy => AppRoute.policy,
      ProfileDestination.notice => throw StateError('opened in the browser'),
    });
  }
}
