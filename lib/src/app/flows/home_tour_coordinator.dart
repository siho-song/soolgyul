import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/errors/error_report.dart';
import '../../features/home_tour/presentation/home_tour_overlay.dart';
import '../../navigation/app_route.dart';
import 'app_gateways.dart';
import 'flow_host.dart';

/// The tour over the home. A member who has no card is shown it once, the
/// first time this phone opens the home for the account; a member who
/// already has a card never is. Without [AppGateways.homeTourMemory] nobody
/// is shown it.
class HomeTourCoordinator {
  HomeTourCoordinator(this._host, this._gateways, {required this.cardCount});

  /// A debug run started with SOOL_HOME_TOUR=true shows the tour every time
  /// the home opens, for design review.
  static const _always = kDebugMode && bool.fromEnvironment('SOOL_HOME_TOUR');

  final FlowHost _host;
  final AppGateways _gateways;

  /// How many cards the account has, or `null` when that is not known now.
  final Future<int?> Function() cardCount;

  final targets = HomeTourTargets();
  final overlayKey = GlobalKey<HomeTourOverlayState>();

  bool active = false;
  bool _deciding = false;

  /// Called when the home comes on screen.
  Future<void> offer() async {
    if (active || _deciding) return;
    _deciding = true;
    try {
      if (await _mayShow()) _start();
    } catch (error, stack) {
      reportError(error, stack, where: 'home tour');
    } finally {
      _deciding = false;
    }
  }

  Future<bool> _mayShow() async {
    if (_always) return true;
    final memory = _gateways.homeTourMemory;
    if (memory == null || await memory.offered()) return false;
    // Not known now: the next time the home opens asks again.
    final cards = await cardCount();
    if (cards == null) return false;
    // A member with a card has seen what the tour explains.
    if (cards > 0) await memory.rememberOffered();
    return cards == 0;
  }

  void _start() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_host.mounted || active) return;
      if (_host.router.currentRoute != AppRoute.home) return;
      _host.refresh(() => active = true);
      _gateways.homeTourMemory?.rememberOffered().ignore();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void end() => _host.refresh(() => active = false);

  /// The system back button: one step back, and off the first step the
  /// tour ends. `false` when no tour is running.
  bool handleBack() {
    if (!active) return false;
    if (overlayKey.currentState?.back() != true) end();
    return true;
  }
}
