import 'dart:async';

import 'package:flutter/material.dart';

import 'app_route.dart';

@immutable
class AppRoutePath {
  const AppRoutePath(this.route);

  final AppRoute route;
}

class AppRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  const AppRouteInformationParser({this.fallback = AppRoute.onboardingWelcome});

  final AppRoute fallback;

  @override
  Future<AppRoutePath> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final uri = routeInformation.uri;
    final usesFallbackAtRoot =
        (uri.path.isEmpty || uri.path == '/') &&
        !uri.queryParameters.containsKey('screen') &&
        fallback != AppRoute.onboardingWelcome;
    return AppRoutePath(
      usesFallbackAtRoot ? fallback : AppRoute.fromUri(uri, fallback: fallback),
    );
  }

  @override
  RouteInformation restoreRouteInformation(AppRoutePath configuration) {
    return RouteInformation(uri: Uri.parse(configuration.route.path));
  }
}

class AppRouter extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  AppRouter({
    required AppRoute initialRoute,
    required this.child,
    this.redirect,
  }) : _stack = _redirected(initialRoute.canonicalStack, redirect);

  final Widget child;

  /// Replaces routes this surface does not serve, e.g. app-only routes on web.
  final AppRoute Function(AppRoute route)? redirect;
  final List<AppRoute> _stack;
  int _revision = 0;

  /// Asked before the header's back or the system back leaves the page on
  /// top: whether to leave. A page holding writing that was not sent sets
  /// it, asks the reader, and takes it away again when the page goes.
  Future<bool> Function()? leaveGuard;
  bool _askingToLeave = false;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  List<AppRoute> get stack => List.unmodifiable(_stack);

  AppRoute get currentRoute => _stack.last;

  bool get canPop => _stack.length > 1;

  @override
  AppRoutePath get currentConfiguration => AppRoutePath(currentRoute);

  void push(AppRoute route) {
    final target = redirect?.call(route) ?? route;
    if (target != route) {
      replaceRoot(target);
      return;
    }
    if (currentRoute == route) {
      return;
    }
    _stack.add(route);
    _notifyRouteChanged();
  }

  /// Takes out the steps right under the route on top, so going back from
  /// it skips them: a finished card's result drops the drink search and
  /// questions behind it. The bottom route always stays.
  void dropStepsBelowTop(bool Function(AppRoute route) isStep) {
    final top = _stack.length - 1;
    var below = top;
    while (below > 1 && isStep(_stack[below - 1])) {
      below -= 1;
    }
    if (below == top) return;
    _stack.removeRange(below, top);
    _notifyRouteChanged();
  }

  void replaceRoot(AppRoute route) {
    _stack
      ..clear()
      ..add(redirect?.call(route) ?? route);
    _notifyRouteChanged();
  }

  void replaceStack(List<AppRoute> routes) {
    assert(routes.isNotEmpty);
    _stack
      ..clear()
      ..addAll(_redirected(routes, redirect));
    _notifyRouteChanged();
  }

  bool pop() {
    if (!canPop) {
      return false;
    }
    if (leaveGuard case final guard?) {
      unawaited(_leaveIfAllowed(guard));
      return true;
    }
    _stack.removeLast();
    _notifyRouteChanged();
    return true;
  }

  Future<void> _leaveIfAllowed(Future<bool> Function() guard) async {
    // A second back while the question is up asks nothing more.
    if (_askingToLeave) return;
    _askingToLeave = true;
    final asked = currentRoute;
    final bool leave;
    try {
      leave = await guard();
    } finally {
      _askingToLeave = false;
    }
    // Only the page that was asked about leaves.
    if (!leave || !canPop || currentRoute != asked) return;
    _stack.removeLast();
    _notifyRouteChanged();
  }

  void didRemovePage(AppRoute route) {
    if (_stack.length <= 1 || _stack.last != route) {
      return;
    }
    _stack.removeLast();
    _notifyRouteChanged();
  }

  /// The system back (Android's button or gesture). What lies open over the
  /// page closes first; only with nothing open does the page itself go.
  @override
  Future<bool> popRoute() async => await popOverlay() || pop();

  /// Closes what lies open over the page on top: a sheet, a popup, a
  /// dropdown list, or a balloon the page keeps in its own history. Whether
  /// there was one; a popup that must be answered stays up and still counts.
  ///
  /// Those are routes the Navigator holds without a page of the stack, so
  /// shortening the stack would take the page from under them instead.
  Future<bool> popOverlay() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return false;
    Route<Object?>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final route = top;
    if (route == null ||
        (route.settings is Page && !route.willHandlePopInternally)) {
      return false;
    }
    return navigator.maybePop();
  }

  /// The browser's back, forward or address bar chose a page. The change is
  /// announced like any other, so the screen is counted.
  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    // The loading screen is where the app starts, never where a link
    // leads: an address the app does not know parses to it on a phone.
    if (configuration.route == AppRoute.appLoading &&
        currentRoute != AppRoute.appLoading) {
      return;
    }
    final nextStack = _redirected(configuration.route.canonicalStack, redirect);
    if (_sameRoutes(_stack, nextStack)) {
      return;
    }
    _stack
      ..clear()
      ..addAll(nextStack);
    _notifyRouteChanged();
  }

  @override
  Widget build(BuildContext context) {
    return AppRouterScope(router: this, revision: _revision, child: child);
  }

  void _notifyRouteChanged() {
    _revision += 1;
    notifyListeners();
  }

  /// A stack containing any redirected route collapses to its target.
  static List<AppRoute> _redirected(
    List<AppRoute> routes,
    AppRoute Function(AppRoute route)? redirect,
  ) {
    if (redirect == null || routes.every((route) => redirect(route) == route)) {
      return routes;
    }
    return redirect(routes.last).canonicalStack;
  }

  static bool _sameRoutes(List<AppRoute> left, List<AppRoute> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

class AppRouterScope extends InheritedWidget {
  const AppRouterScope({
    super.key,
    required this.router,
    required this.revision,
    required super.child,
  });

  final AppRouter router;
  final int revision;

  static AppRouter of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppRouterScope>();
    assert(scope != null, 'AppRouterScope is required');
    return scope!.router;
  }

  /// The router, or null on a screen shown outside the app's router.
  static AppRouter? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppRouterScope>()?.router;

  @override
  bool updateShouldNotify(AppRouterScope oldWidget) {
    return revision != oldWidget.revision;
  }
}
