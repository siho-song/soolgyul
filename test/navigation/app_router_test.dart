import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/navigation/app_route.dart';
import 'package:soolgyul/src/navigation/app_router.dart';

void main() {
  test('route paths and legacy debug names resolve to typed routes', () {
    expect(
      AppRoute.fromUri(Uri.parse('/?screen=record-entry')),
      AppRoute.recordEntry,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/record/search')),
      AppRoute.recordSearch,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/?screen=record-start')),
      AppRoute.recordSearch,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/?screen=main#/home/letters')),
      AppRoute.soolgyulLetters,
    );
    expect(AppRoute.fromUri(Uri.parse('/home/fit')), AppRoute.tasteFitSearch);
    expect(
      AppRoute.fromUri(Uri.parse('/home/fit/detail')),
      AppRoute.tasteFitDetail,
    );
    expect(AppRoute.fromLegacyName('fit-search'), AppRoute.tasteFitSearch);
    expect(AppRoute.fromLegacyName('fit-detail'), AppRoute.tasteFitDetail);
    expect(AppRoute.fromDebugScreen(76), AppRoute.tasteFitSearch);
    expect(AppRoute.fromDebugScreen(77), AppRoute.tasteFitDetail);
    expect(AppRoute.fromDebugScreen(53), AppRoute.soolgyulLetters);
    expect(AppRoute.fromDebugScreen(54), AppRoute.savedArticles);
    expect(
      AppRoute.fromUri(Uri.parse('/home/letters')),
      AppRoute.soolgyulLetters,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/profile/saved-articles')),
      AppRoute.savedArticles,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/profile/support/inquiry')),
      AppRoute.supportInquiry,
    );
  });

  test('direct links cannot bypass the required drink-name step', () {
    expect(
      AppRoute.fromUri(Uri.parse('/onboarding/result')),
      AppRoute.onboardingWelcome,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/?screen=result')),
      AppRoute.onboardingWelcome,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/onboarding/profile/interests')),
      AppRoute.onboardingWelcome,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/record/questions')),
      AppRoute.recordSearch,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/onboarding/search')),
      AppRoute.onboardingSearch,
    );
    expect(
      AppRoute.fromUri(Uri.parse('/onboarding/revisit')),
      AppRoute.onboardingWelcome,
    );
  });

  test('unknown entry points fall back', () {
    expect(AppRoute.fromDebugScreen(999), AppRoute.onboardingWelcome);
    expect(
      AppRoute.fromUri(Uri.parse('/'), fallback: AppRoute.home),
      AppRoute.onboardingWelcome,
    );
  });

  test('every typed route has a unique debug screen ID', () {
    final debugScreens = AppRoute.values
        .map((route) => route.debugScreen)
        .toSet();

    expect(debugScreens, hasLength(AppRoute.values.length));
  });

  test('semantic route sections classify every typed route', () {
    final routesBySection = <AppRouteSection, Set<AppRoute>>{
      for (final section in AppRouteSection.values)
        section: AppRoute.values
            .where((route) => route.section == section)
            .toSet(),
    };

    expect(
      routesBySection.values.expand((routes) => routes).toSet(),
      AppRoute.values.toSet(),
    );
    expect(
      AppRoute.values.where((route) => route.isMainTabRoot).toSet(),
      <AppRoute>{
        AppRoute.home,
        AppRoute.preference,
        AppRoute.recordEntry,
        AppRoute.explore,
        AppRoute.profile,
      },
    );
    expect(
      AppRoute.values.where((route) => route.isOnboarding).toSet(),
      routesBySection[AppRouteSection.onboarding],
    );
  });

  test('detail routes provide a canonical back stack for direct links', () {
    expect(AppRoute.home.canonicalStack, <AppRoute>[AppRoute.home]);
    expect(AppRoute.soolgyulLetters.canonicalStack, <AppRoute>[
      AppRoute.home,
      AppRoute.soolgyulLetters,
    ]);
    expect(AppRoute.tasteFitDetail.canonicalStack, <AppRoute>[
      AppRoute.home,
      AppRoute.tasteFitSearch,
      AppRoute.tasteFitDetail,
    ]);
    expect(AppRoute.savedArticles.canonicalStack, <AppRoute>[
      AppRoute.profile,
      AppRoute.savedArticles,
    ]);
    expect(AppRoute.supportInquiry.canonicalStack, <AppRoute>[
      AppRoute.profile,
      AppRoute.supportCenter,
      AppRoute.supportInquiry,
    ]);
    expect(AppRoute.recordQuestions.canonicalStack, <AppRoute>[
      AppRoute.recordEntry,
      AppRoute.recordSearch,
      AppRoute.recordQuestions,
    ]);
    expect(AppRoute.onboardingResult.canonicalStack, <AppRoute>[
      AppRoute.onboardingWelcome,
      AppRoute.onboardingSearch,
      AppRoute.onboardingQuestions,
      AppRoute.onboardingResult,
    ]);
  });

  testWidgets('router push, pop and root replacement update the page stack', (
    tester,
  ) async {
    late AppRouter router;
    router = AppRouter(
      initialRoute: AppRoute.home,
      child: Builder(
        builder: (context) {
          final navigation = AppRouterScope.of(context);
          return Navigator(
            key: navigation.navigatorKey,
            pages: <Page<void>>[
              for (final route in navigation.stack)
                MaterialPage<void>(
                  key: ValueKey(route),
                  child: Text(route.path, textDirection: TextDirection.ltr),
                ),
            ],
            onDidRemovePage: (page) {
              navigation.didRemovePage((page.key! as ValueKey<AppRoute>).value);
            },
          );
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerDelegate: router,
        routeInformationParser: const AppRouteInformationParser(
          fallback: AppRoute.home,
        ),
      ),
    );
    await tester.pumpAndSettle();

    router.push(AppRoute.soolgyulLetters);
    await tester.pumpAndSettle();
    expect(router.stack, <AppRoute>[AppRoute.home, AppRoute.soolgyulLetters]);

    expect(await router.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(router.currentRoute, AppRoute.home);

    router.replaceRoot(AppRoute.profile);
    await tester.pumpAndSettle();
    expect(router.stack, <AppRoute>[AppRoute.profile]);
  });

  test('a page the browser chose is announced; a link never reopens '
      'loading', () async {
    final router = AppRouter(
      initialRoute: AppRoute.home,
      child: const SizedBox(),
    );
    addTearDown(router.dispose);
    var announced = 0;
    router.addListener(() => announced++);

    await router.setNewRoutePath(const AppRoutePath(AppRoute.soolgyulLetters));
    expect(router.stack, <AppRoute>[AppRoute.home, AppRoute.soolgyulLetters]);
    expect(announced, 1);

    // The same page again changes nothing.
    await router.setNewRoutePath(const AppRoutePath(AppRoute.soolgyulLetters));
    expect(announced, 1);

    // An address the phone does not know, such as /claim, parses to the
    // loading screen; the member stays where they are.
    final parsed = await const AppRouteInformationParser(
      fallback: AppRoute.appLoading,
    ).parseRouteInformation(RouteInformation(uri: Uri.parse('/claim?r=1')));
    expect(parsed.route, AppRoute.appLoading);
    await router.setNewRoutePath(parsed);
    expect(router.stack, <AppRoute>[AppRoute.home, AppRoute.soolgyulLetters]);
    expect(announced, 1);
  });

  test('a finished card drops the search and questions under it', () {
    final router = AppRouter(
      initialRoute: AppRoute.onboardingWelcome,
      child: const SizedBox(),
    );
    addTearDown(router.dispose);
    router
      ..push(AppRoute.onboardingSearch)
      ..push(AppRoute.onboardingQuestions)
      ..push(AppRoute.onboardingResult)
      ..dropStepsBelowTop((route) => route.leadsToNewCard);
    // The first card goes back to the welcome screen.
    expect(router.stack, <AppRoute>[
      AppRoute.onboardingWelcome,
      AppRoute.onboardingResult,
    ]);

    // A member whose first card starts from a tab goes back to the tab,
    // past the intro.
    router
      ..replaceStack(<AppRoute>[
        AppRoute.home,
        AppRoute.onboardingWelcome,
        AppRoute.onboardingSearch,
        AppRoute.onboardingQuestions,
        AppRoute.onboardingResult,
      ])
      ..dropStepsBelowTop((route) => route.leadsToNewCard);
    expect(router.stack, <AppRoute>[AppRoute.home, AppRoute.onboardingResult]);

    // A record goes back to the tab it began from; the bottom route stays
    // even when it is a step.
    router
      ..replaceStack(<AppRoute>[
        AppRoute.recordSearch,
        AppRoute.recordQuestions,
        AppRoute.onboardingResult,
      ])
      ..dropStepsBelowTop((route) => route.leadsToNewCard);
    expect(router.stack, <AppRoute>[
      AppRoute.recordSearch,
      AppRoute.onboardingResult,
    ]);
  });
}
