enum AppRouteSection {
  /// The mobile app's start: loading, then login.
  entry,
  onboarding,
  home,
  preference,
  explore,
  profile,
  recording,
}

enum AppRoute {
  onboardingWelcome('/', 0),
  onboardingSearch('/onboarding/search', 1),
  onboardingQuestions('/onboarding/questions', 3),
  onboardingResult('/onboarding/result', 9),
  profileSetup('/onboarding/profile', 11),
  home('/home', 13),
  preference('/preference', 14),
  explore('/explore', 15),
  profile('/profile', 16),
  policy('/profile/policy', 24),
  recordQuestions('/record/questions', 43),
  recordSearch('/record/search', 51),
  soolgyulLetters('/home/letters', 53),
  supportInquiry('/profile/support/inquiry', 55),
  editorialArticle('/explore/article', 58),
  appLoading('/loading', 74),
  appLogin('/login', 75),
  tasteFitSearch('/home/fit', 76),
  tasteFitDetail('/home/fit/detail', 77),
  savedDrinks('/profile/saved-drinks', 78),
  savedTerms('/profile/saved-terms', 79),
  historySearch('/preference/search', 80);

  const AppRoute(this.path, this.debugScreen);

  final String path;
  final int debugScreen;

  AppRouteSection get section => switch (this) {
    appLoading || appLogin => AppRouteSection.entry,
    onboardingWelcome ||
    onboardingSearch ||
    onboardingQuestions ||
    onboardingResult ||
    profileSetup => AppRouteSection.onboarding,
    home ||
    soolgyulLetters ||
    tasteFitSearch ||
    tasteFitDetail => AppRouteSection.home,
    preference || historySearch => AppRouteSection.preference,
    explore || editorialArticle => AppRouteSection.explore,
    profile ||
    savedDrinks ||
    savedTerms ||
    supportInquiry ||
    policy => AppRouteSection.profile,
    recordSearch || recordQuestions => AppRouteSection.recording,
  };

  bool get isOnboarding => section == AppRouteSection.onboarding;

  /// The web serves the first-record onboarding only, as a taste of the
  /// app; every other page is the app's, and a link to one starts over.
  bool get isAvailableOnWeb => section == AppRouteSection.onboarding;

  AppRoute get webRoute => isAvailableOnWeb ? this : onboardingWelcome;

  /// Whether this route is downstream of the required drink-name step.
  ///
  /// A fresh app process has no in-memory draft, so direct links to these
  /// routes must restart at the corresponding named-drink entry flow.
  bool get requiresNamedDrinkDraft => switch (this) {
    onboardingQuestions ||
    onboardingResult ||
    profileSetup ||
    recordQuestions => true,
    _ => false,
  };

  /// The intro, drink search and questions a new card is made from; its
  /// result takes their place. The intro stays when it is where the app
  /// began (a first visit), as the bottom route always does.
  bool get leadsToNewCard => switch (this) {
    onboardingWelcome ||
    onboardingSearch ||
    onboardingQuestions ||
    recordSearch ||
    recordQuestions => true,
    _ => false,
  };

  AppRoute get safeDirectEntryRoute {
    if (!requiresNamedDrinkDraft) {
      return this;
    }
    return section == AppRouteSection.recording
        ? recordSearch
        : onboardingWelcome;
  }

  bool get isMainTabRoot =>
      this == home || this == preference || this == explore || this == profile;

  AppRoute? get canonicalParent => switch (this) {
    appLoading ||
    appLogin ||
    onboardingWelcome ||
    home ||
    preference ||
    explore ||
    profile => null,
    onboardingSearch => onboardingWelcome,
    onboardingQuestions => onboardingSearch,
    onboardingResult => onboardingQuestions,
    // Profile setup follows the app's login.
    profileSetup => appLogin,
    // A record is started from home's 기록하기.
    soolgyulLetters || tasteFitSearch || recordSearch => home,
    tasteFitDetail => tasteFitSearch,
    savedDrinks || savedTerms || supportInquiry || policy => profile,
    historySearch => preference,
    editorialArticle => explore,
    recordQuestions => recordSearch,
  };

  List<AppRoute> get canonicalStack {
    final routes = <AppRoute>[];
    AppRoute? current = this;
    while (current != null) {
      routes.insert(0, current);
      current = current.canonicalParent;
    }
    return routes;
  }

  static AppRoute fromUri(
    Uri uri, {
    AppRoute fallback = AppRoute.onboardingWelcome,
  }) {
    final fragmentPath = uri.fragment.startsWith('/') ? uri.fragment : null;
    final routedPath = fragmentPath ?? (uri.path.isEmpty ? '/' : uri.path);
    if (routedPath != '/') {
      final route = values.firstWhere(
        (route) => route.path == routedPath,
        orElse: () => fallback,
      );
      return route.safeDirectEntryRoute;
    }

    final requested = uri.queryParameters['screen'];
    if (requested != null) {
      return fromLegacyName(requested, fallback: fallback).safeDirectEntryRoute;
    }
    return onboardingWelcome;
  }

  static AppRoute fromDebugScreen(
    int screen, {
    AppRoute fallback = AppRoute.onboardingWelcome,
  }) {
    return values.firstWhere(
      (route) => route.debugScreen == screen,
      orElse: () => fallback,
    );
  }

  static AppRoute fromLegacyName(
    String? name, {
    AppRoute fallback = AppRoute.onboardingWelcome,
  }) {
    return switch (name) {
      'loading' => appLoading,
      'app-login' => appLogin,
      'onboarding-search' => onboardingSearch,
      'result' => onboardingResult,
      'profile-setup' ||
      'post-name' ||
      'post-pref' ||
      'post-confirmation' => profileSetup,
      'main' => home,
      'preference' => preference,
      'explore' => explore,
      'my' => profile,
      'saved-drinks' => savedDrinks,
      'saved-terms' => savedTerms,
      'history-search' => historySearch,
      // The 고객지원 page that led to the form is gone: its name opens the form.
      'support' || 'support-inquiry' => supportInquiry,
      'terms' => policy,
      'editorial-article' => editorialArticle,
      'soolgyul-letters' => soolgyulLetters,
      'fit-search' => tasteFitSearch,
      'fit-detail' => tasteFitDetail,
      // The record tab of the five-tab bar is gone: its name opens the
      // drink search a record starts with.
      'record-start' || 'record-search' || 'record-entry' => recordSearch,
      'record-questions' => recordQuestions,
      _ => fallback,
    };
  }
}
