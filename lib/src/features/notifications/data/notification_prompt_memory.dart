import 'package:shared_preferences/shared_preferences.dart';

import 'notification_access.dart';

/// How often a member is asked to turn notifications on, at most.
const notificationPromptMaxAsks = 2;

/// The shortest wait between two asks.
const notificationPromptGap = Duration(days: 7);

/// What this phone remembers of asking one member.
class NotificationPromptRecord {
  const NotificationPromptRecord({this.asks = 0, this.lastAsked});

  /// Asks the member answered with "not now".
  final int asks;
  final DateTime? lastAsked;
}

/// Whether the member may be asked now: notifications are off but not
/// refused by the phone, and the member has not been asked too often or too
/// recently.
bool mayAskForNotifications({
  required NotificationStatus status,
  required NotificationPromptRecord record,
  required DateTime now,
}) {
  if (status != NotificationStatus.off) return false;
  if (record.asks >= notificationPromptMaxAsks) return false;
  final last = record.lastAsked;
  return last == null || now.difference(last) >= notificationPromptGap;
}

/// Remembers, on this phone and per account, the asks a member turned down.
abstract interface class NotificationPromptMemory {
  /// `null` when nobody is signed in.
  Future<NotificationPromptRecord?> read();

  /// The member was asked at [at] and did not turn notifications on.
  Future<void> rememberAsked(DateTime at);

  /// The member turned notifications off by hand: no more asking.
  Future<void> rememberTurnedOff();
}

class DeviceNotificationPromptMemory implements NotificationPromptMemory {
  DeviceNotificationPromptMemory({required this.accountId});

  /// The signed-in account, or `null`.
  final String? Function() accountId;

  String? get _asksKey => switch (accountId()) {
    final id? => 'notification-prompt.$id.asks',
    null => null,
  };

  String? get _lastKey => switch (accountId()) {
    final id? => 'notification-prompt.$id.last',
    null => null,
  };

  @override
  Future<NotificationPromptRecord?> read() async {
    final asksKey = _asksKey;
    final lastKey = _lastKey;
    if (asksKey == null || lastKey == null) return null;
    final preferences = await SharedPreferences.getInstance();
    final last = preferences.getInt(lastKey);
    return NotificationPromptRecord(
      asks: preferences.getInt(asksKey) ?? 0,
      lastAsked: last == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  @override
  Future<void> rememberAsked(DateTime at) async {
    final asksKey = _asksKey;
    final lastKey = _lastKey;
    if (asksKey == null || lastKey == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(asksKey, (preferences.getInt(asksKey) ?? 0) + 1);
    await preferences.setInt(lastKey, at.millisecondsSinceEpoch);
  }

  @override
  Future<void> rememberTurnedOff() async {
    final asksKey = _asksKey;
    if (asksKey == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(asksKey, notificationPromptMaxAsks);
  }
}
