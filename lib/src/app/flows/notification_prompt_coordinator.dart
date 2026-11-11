import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/errors/error_report.dart';
import '../../features/notifications/data/notification_access.dart';
import '../../features/notifications/data/notification_prompt_memory.dart';
import '../../features/notifications/presentation/notification_prompt_sheet.dart';
import '../../navigation/app_route.dart';
import 'app_gateways.dart';
import 'flow_host.dart';

/// Asks a member to turn notifications on, at a moment the app has just
/// been of use: back from a bottle's fit, or after a card that is not the
/// first. Without [AppGateways.notifications] nobody is asked.
class NotificationPromptCoordinator {
  NotificationPromptCoordinator(
    this._host,
    this._gateways, {
    required this.pagesSettled,
    this.now = DateTime.now,
  });

  final FlowHost _host;
  final AppGateways _gateways;
  final DateTime Function() now;

  /// Completes once no page is still moving away. A sheet opened over a
  /// leaving page would go away with it.
  final Future<void> Function() pagesSettled;
  bool _busy = false;

  /// A page takes well under a second to move away.
  static const _longestWait = Duration(seconds: 3);

  /// Shows the question on the page the member has just arrived at, when
  /// the member may be asked now.
  Future<void> offer() async {
    final access = _gateways.notifications;
    final memory = _gateways.notificationPromptMemory;
    if (_busy || access == null || memory == null || _gateways.isWeb) return;
    _busy = true;
    try {
      final record = await memory.read();
      if (record == null) return;
      final allowed = mayAskForNotifications(
        status: await access.load(),
        record: record,
        now: now(),
      );
      if (!allowed) return;
      final route = _host.router.currentRoute;
      // One frame for the navigator to take the new pages in, then the wait
      // for the page that was left.
      await WidgetsBinding.instance.endOfFrame;
      await pagesSettled().timeout(_longestWait);
      if (!_host.mounted || _host.router.currentRoute != route) return;
      final context = _host.router.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final accepted = await showNotificationPromptSheet(context);
      if (accepted != true) {
        await memory.rememberAsked(now());
        return;
      }
      final NotificationStatus status;
      try {
        status = await access.turnOn();
      } catch (error, stack) {
        reportError(error, stack, where: 'notification prompt');
        if (_host.mounted) {
          _host.showFeedback('알림을 켜지 못했어요. 잠시 후 마이페이지에서 다시 켜 주세요.');
        }
        return;
      }
      if (status != NotificationStatus.on) {
        await memory.rememberAsked(now());
        return;
      }
      await _agreeToMarketing();
    } on TimeoutException {
      // The page never came to rest: the next moment asks instead.
    } catch (error, stack) {
      reportError(error, stack, where: 'notification prompt');
    } finally {
      _busy = false;
    }
  }

  /// The question says that turning notifications on agrees to marketing
  /// ones; the agreement is saved only once the phone allowed them.
  Future<void> _agreeToMarketing() async {
    try {
      await _gateways.marketingConsent?.save(true);
    } catch (_) {
      if (_host.mounted) {
        _host.showFeedback('알림은 켰지만 수신 동의를 저장하지 못했어요. 마이페이지에서 다시 켜 주세요.');
      }
      return;
    }
    if (_host.mounted) _host.showFeedback('맞춤 알림을 켰어요.', success: true);
  }
}

/// Whether leaving [previous] for [current] is a moment to ask:
/// back from a bottle's fit to the search, or away from a card that was
/// just saved and is not the member's first ([newRepeatCard]).
bool isNotificationPromptMoment({
  required AppRoute? previous,
  required AppRoute current,
  required bool newRepeatCard,
}) {
  if (previous == current) return false;
  if (previous == AppRoute.tasteFitDetail) {
    return current == AppRoute.tasteFitSearch;
  }
  return previous == AppRoute.onboardingResult && newRepeatCard;
}

/// Watches a navigator for pages that are still moving away.
class LeavingPagesObserver extends NavigatorObserver {
  final _leaving = <Future<void>>{};

  /// Completes once every page that was leaving is gone, those that start
  /// to leave meanwhile too.
  Future<void> settled() async {
    while (_leaving.isNotEmpty) {
      await Future.wait(_leaving.toList());
    }
  }

  void _watch(Route<dynamic>? route) {
    if (route is! TransitionRoute) return;
    late final Future<void> gone;
    gone = route.completed
        .then<void>((_) {}, onError: (_) {})
        .whenComplete(() => _leaving.remove(gone));
    _leaving.add(gone);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _watch(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _watch(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _watch(oldRoute);
}
