part of 'app_flow.dart';

const MethodChannel _debugScreenChannel = MethodChannel(
  'soolgyul/debug-screen',
);

final class _AppFlowDebugState {
  int selectedView = 0;
  bool reviewActive = false;
  bool requestedNativeScreen = false;
}

/// Development entry points: the native numbered-screen launcher and the
/// design lab review overlay. No product flow depends on this.
extension _AppFlowDebugActions on _AppFlowState {
  void _requestNativeDebugScreenOnce() {
    if (_debug.requestedNativeScreen) {
      return;
    }
    _debug.requestedNativeScreen = true;
    unawaited(_openRequestedDebugScreen());
  }

  Future<void> _openRequestedDebugScreen() async {
    try {
      final requestedDebugScreen = await _debugScreenChannel.invokeMethod<int>(
        'getRequestedScreen',
      );
      if (!mounted || requestedDebugScreen == null) {
        return;
      }

      final isRegistered = AppRoute.values.any(
        (route) => route.debugScreen == requestedDebugScreen,
      );
      if (isRegistered) {
        final requestedRoute = AppRoute.fromDebugScreen(requestedDebugScreen);
        final targetRoute = kDebugMode
            ? requestedRoute
            : requestedRoute.safeDirectEntryRoute;
        _seedRequiredDrinkForDebug(targetRoute);
        router.replaceRoot(targetRoute);
      }
    } on MissingPluginException {
      // Web and iOS keep using SOOL_SCREEN or the normal app flow.
    }
  }

  void _openDesignReviewScreen(int targetScreen) {
    final route = AppRoute.fromDebugScreen(targetScreen);
    refresh(() {
      _debug.reviewActive = true;
      _seedRequiredDrinkForDebug(route);
    });
    router.push(route);
  }

  void _returnToDesignLab() {
    refresh(() => _debug.reviewActive = false);
    router.replaceRoot(AppRoute.designLab);
  }

  void _seedRequiredDrinkForDebug(AppRoute route) {
    if (!kDebugMode || !route.requiresNamedDrinkDraft) {
      return;
    }
    if (route.section == AppRouteSection.onboarding &&
        !_onboarding.state.entryDraft.canContinue) {
      _onboarding.state.startWith(
        OnboardingEntryDraft.fromDrinkSelection(
          const DrinkSelection.catalogMatch(
            AdaptiveOnboardingTestCatalog.dryWhiteWine,
          ),
        ),
      );
    }
    if (route.section == AppRouteSection.recording &&
        _record.state.drinkSelection == null) {
      _record.state.continueWithDrinkSelection(
        const DrinkSelection.catalogMatch(
          AdaptiveOnboardingTestCatalog.dryWhiteWine,
        ),
      );
    }
  }
}
