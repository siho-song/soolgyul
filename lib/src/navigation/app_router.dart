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
    _stack.removeLast();
    _notifyRouteChanged();
    return true;
  }

  void didRemovePage(AppRoute route) {
    if (_stack.length <= 1 || _stack.last != route) {
      return;
    }
    _stack.removeLast();
    _notifyRouteChanged();
  }

  @override
  Future<bool> popRoute() async => pop();

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    final nextStack = _redirected(configuration.route.canonicalStack, redirect);
    if (_sameRoutes(_stack, nextStack)) {
      return;
    }
    _stack
      ..clear()
      ..addAll(nextStack);
    _revision += 1;
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
    assert(scope != null, 'AppRouterScope가 필요합니다.');
    return scope!.router;
  }

  @override
  bool updateShouldNotify(AppRouterScope oldWidget) {
    return revision != oldWidget.revision;
  }
}
