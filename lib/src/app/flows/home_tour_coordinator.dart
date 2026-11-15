import 'dart:async';

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

  /// The offer being decided on, or the last one decided.
  Future<void> _offer = Future<void>.value();

  /// The tour was decided on and comes up with the next frame.
  bool _starting = false;

  /// Whoever waits in [whenOver] for the tour to close.
  Completer<void>? _over;

  /// Called when the home comes on screen.
  Future<void> offer() {
    if (active || _deciding) return Future<void>.value();
    return _offer = _decide();
  }

  Future<void> _decide() async {
    _deciding = true;
    try {
      if (await _mayShow()) _start();
    } catch (error, stack) {
      reportError(error, stack, where: 'home tour');
    } finally {
      _deciding = false;
    }
  }

  /// For a notice the tour would cover: ends at once when no tour is on the
  /// home or about to be, and otherwise when the tour has closed.
  Future<void> whenOver() async {
    await _offer;
    if (_starting || active) await (_over ??= Completer<void>()).future;
  }

  void _noLongerInTheWay() {
    _over?.complete();
    _over = null;
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
    _starting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _starting = false;
      if (!_host.mounted || active) return;
      if (_host.router.currentRoute != AppRoute.home) {
        _noLongerInTheWay();
        return;
      }
      _host.refresh(() => active = true);
      _gateways.homeTourMemory?.rememberOffered().ignore();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void end() {
    _host.refresh(() => active = false);
    _noLongerInTheWay();
  }

  /// The system back button: one step back, and off the first step the
  /// tour ends. `false` when no tour is running.
  bool handleBack() {
    if (!active) return false;
    if (overlayKey.currentState?.back() != true) end();
    return true;
  }
}
