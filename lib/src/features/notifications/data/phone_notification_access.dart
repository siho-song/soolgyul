import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/error_report.dart';
import 'notification_access.dart';

/// What the phone itself says about showing the app's notifications.
enum PhonePermission { allowed, notAsked, refused }

/// The phone's side of notifications: its permission and its address at the
/// notification service.
abstract interface class PhoneNotifications {
  Future<PhonePermission> permission();

  /// Shows the phone's own question.
  Future<PhonePermission> ask();

  Future<String> address();

  /// The new address, whenever the service changes it.
  Stream<String> get addressChanges;

  Future<void> openSettings();
}

/// The server's list of the phones a member has notifications on for.
abstract interface class PushDeviceRegistry {
  Future<void> register(String address);

  Future<void> forget(String address);
}

/// [NotificationAccess] on a real phone. Notifications are on when the
/// member turned them on for this account on this phone and the phone
/// allows them; the phone's address is then kept at the server.
class PhoneNotificationAccess implements NotificationAccess {
  PhoneNotificationAccess({
    required this.phone,
    required this.registry,
    required this.accountId,
  }) {
    _addressChanges = phone.addressChanges.listen(
      (address) => unawaited(_registerIfOn(() async => address)),
      onError: (Object _) {},
    );
  }

  final PhoneNotifications phone;
  final PushDeviceRegistry registry;

  /// The signed-in account, or `null`.
  final String? Function() accountId;
  late final StreamSubscription<String> _addressChanges;

  /// Signing out never waits longer than this for the server to forget.
  static const _signOutWait = Duration(seconds: 3);

  String? get _onKey => switch (accountId()) {
    final id? => 'notifications.$id.on',
    null => null,
  };

  Future<bool> _turnedOn() async {
    final key = _onKey;
    if (key == null) return false;
    return (await SharedPreferences.getInstance()).getBool(key) ?? false;
  }

  Future<void> _remember(bool on) async {
    final key = _onKey;
    if (key == null) return;
    await (await SharedPreferences.getInstance()).setBool(key, on);
  }

  @override
  Future<NotificationStatus> load() async => switch (await phone.permission()) {
    PhonePermission.refused => NotificationStatus.blocked,
    PhonePermission.allowed when await _turnedOn() => NotificationStatus.on,
    _ => NotificationStatus.off,
  };

  @override
  Future<NotificationStatus> turnOn() async {
    var permission = await phone.permission();
    if (permission == PhonePermission.notAsked) permission = await phone.ask();
    switch (permission) {
      case PhonePermission.refused:
        return NotificationStatus.blocked;
      case PhonePermission.notAsked:
        // The phone's question was put away without an answer.
        return NotificationStatus.off;
      case PhonePermission.allowed:
        await registry.register(await phone.address());
        await _remember(true);
        return NotificationStatus.on;
    }
  }

  @override
  Future<NotificationStatus> turnOff() async {
    await registry.forget(await phone.address());
    await _remember(false);
    return load();
  }

  @override
  Future<void> openPhoneSettings() => phone.openSettings();

  @override
  Future<void> resume() => _registerIfOn(phone.address);

  @override
  Future<void> forgetThisPhone() async {
    try {
      if (!await _turnedOn()) return;
      await registry.forget(await phone.address()).timeout(_signOutWait);
    } catch (error, stack) {
      reportError(error, stack, where: 'notification sign-out');
    }
  }

  Future<void> _registerIfOn(Future<String> Function() address) async {
    try {
      if (!await _turnedOn()) return;
      if (await phone.permission() != PhonePermission.allowed) return;
      await registry.register(await address());
    } catch (error, stack) {
      reportError(error, stack, where: 'notification address');
    }
  }

  void dispose() => unawaited(_addressChanges.cancel());
}
