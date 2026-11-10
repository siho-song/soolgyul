import 'dart:async';

import '../../features/taste_card/data/claim_link.dart';
import '../../features/taste_card/data/taste_card_result.dart';
import '../../navigation/app_route.dart';
import 'app_gateways.dart';
import 'flow_host.dart';
import 'taste_card_coordinator.dart';

/// Brings a card made on the web into the app. The ticket arrives as a
/// link opened in the app (handed over by the host) or, on a fresh Android install, as the Play
/// install referrer. A signed-in account claims it at once; otherwise it
/// waits for the sign-in and is claimed on the way to home.
class ClaimCoordinator {
  ClaimCoordinator(this._host, this._gateways, this._tasteCard);

  final FlowHost _host;
  final AppGateways _gateways;
  final TasteCardCoordinator _tasteCard;

  TasteCardPendingConversion? _pending;

  bool get hasPending => _pending != null;

  void start() {
    unawaited(_receiveInstallReferrer());
  }

  Future<void> _receiveInstallReferrer() async {
    final read = _gateways.installReferrer;
    if (read == null) return;
    try {
      final ticket = TasteCardClaimLink.parseInstallReferrer(await read());
      if (ticket != null) receive(ticket);
    } catch (_) {
      // Without the referrer the card simply stays on the web.
    }
  }

  void receiveLink(Uri uri) {
    final ticket = TasteCardClaimLink.parse(uri);
    if (ticket != null) receive(ticket);
  }

  /// A ticket while the app is open and signed in is claimed right away;
  /// before that it waits for the sign-in.
  void receive(TasteCardPendingConversion ticket) {
    _pending = ticket;
    if (!_host.mounted) return;
    final signedIn = _gateways.tasteCard?.isAuthenticated ?? false;
    final route = _host.router.currentRoute;
    if (!signedIn ||
        route == AppRoute.appLoading ||
        route == AppRoute.appLogin ||
        route == AppRoute.profileSetup) {
      return;
    }
    if (route != AppRoute.onboardingResult) {
      _host.router.push(AppRoute.onboardingResult);
    }
    unawaited(claimPending());
  }

  /// Claims the waiting ticket for the signed-in account. True when a
  /// ticket was there, whether or not the card came back; the result
  /// route then shows the card or the retry.
  Future<bool> claimPending() async {
    final ticket = _pending;
    if (ticket == null) return false;
    _pending = null;
    await _tasteCard.claim(ticket);
    return true;
  }

  void resetAfterSignOut() {
    _pending = null;
  }
}
