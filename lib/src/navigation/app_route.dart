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
  savedCards('/profile/saved-cards', 20),
  supportCenter('/profile/support', 22),
  policy('/profile/policy', 24),
  recordQuestions('/record/questions', 43),
  recordEntry('/record', 49),
  recordSearch('/record/search', 51),
  soolgyulLetters('/home/letters', 53),
  savedArticles('/profile/saved-articles', 54),
  supportInquiry('/profile/support/inquiry', 55),
  editorialArticle('/explore/article', 58),
  appLoading('/loading', 74),
  appLogin('/login', 75),
  tasteFitSearch('/home/fit', 76),
  tasteFitDetail('/home/fit/detail', 77);

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
    preference => AppRouteSection.preference,
    explore || editorialArticle => AppRouteSection.explore,
    profile ||
    savedCards ||
    savedArticles ||
    supportCenter ||
    supportInquiry ||
    policy => AppRouteSection.profile,
    recordEntry || recordSearch || recordQuestions => AppRouteSection.recording,
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

  /// The drink search and questions a new card is made from; its result
  /// takes their place.
  bool get leadsToNewCard => switch (this) {
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

  /// 공통 화면 프레임에서 표시하는 최상단 페이지 설명입니다.
  ///
  /// 온보딩과 기록 플로우처럼 화면 내부 질문 설명을 소유하는 경로는 `null`이며,
  /// 해당 공통 레이아웃에서 같은 `pageDescription` 역할을 사용합니다.
  String? get pageDescription => switch (this) {
    supportCenter => '이용 중 궁금한 점이나 불편한 사항을 언제든 남겨주세요.',
    supportInquiry => '문의 유형을 고르고 내용을 작성해 주세요.\n답변은 남겨주신 이메일로 보내드릴게요.',
    policy => '서비스 이용약관 및 개인정보 처리방침을 확인할 수 있어요.',
    _ => null,
  };

  bool get isMainTabRoot =>
      this == home ||
      this == preference ||
      this == explore ||
      this == profile ||
      this == recordEntry;

  AppRoute? get canonicalParent => switch (this) {
    appLoading ||
    appLogin ||
    onboardingWelcome ||
    home ||
    preference ||
    explore ||
    profile ||
    recordEntry => null,
    onboardingSearch => onboardingWelcome,
    onboardingQuestions => onboardingSearch,
    onboardingResult => onboardingQuestions,
    // Profile setup follows the app's login.
    profileSetup => appLogin,
    soolgyulLetters || tasteFitSearch => home,
    tasteFitDetail => tasteFitSearch,
    savedCards || savedArticles || supportCenter || policy => profile,
    supportInquiry => supportCenter,
    editorialArticle => explore,
    recordSearch => recordEntry,
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
      'saved-cards' => savedCards,
      'saved-articles' => savedArticles,
      'support' => supportCenter,
      'support-inquiry' => supportInquiry,
      'terms' => policy,
      'editorial-article' => editorialArticle,
      'soolgyul-letters' => soolgyulLetters,
      'fit-search' => tasteFitSearch,
      'fit-detail' => tasteFitDetail,
      'record-start' || 'record-search' => recordSearch,
      'record-questions' => recordQuestions,
      'record-entry' => recordEntry,
      _ => fallback,
    };
  }
}
