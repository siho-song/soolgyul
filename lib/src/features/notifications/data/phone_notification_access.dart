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

  /// Throws [PhoneAddressNotReady] while the service has given none.
  Future<String> address();

  /// The new address, whenever the service changes it.
  Stream<String> get addressChanges;

  Future<void> openSettings();
}

/// The phone has no address at the notification service yet. An iPhone
/// gets its own from Apple a moment after notifications are first allowed.
class PhoneAddressNotReady implements Exception {
  const PhoneAddressNotReady();

  @override
  String toString() => 'the phone has no notification address yet';
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
    this.addressWait = const Duration(seconds: 1),
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

  /// The pause before the phone is asked for its address again.
  final Duration addressWait;
  late final StreamSubscription<String> _addressChanges;

  /// Turning on asks for the address this many times before going on
  /// without it.
  static const _addressTries = 3;

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
      // Asked, and still no answer: an Android phone before 13 has no
      // question to show, and says only this when its settings refuse. A
      // question put away reads the same. The settings are the way left.
      case PhonePermission.notAsked:
        return NotificationStatus.blocked;
      case PhonePermission.allowed:
        // Without an address the choice is kept all the same: the address
        // reaches the server when it arrives (see [_registerIfOn]).
        final address = await _addressSoon();
        if (address != null) await registry.register(address);
        await _remember(true);
        return NotificationStatus.on;
    }
  }

  /// The phone's address, waited for a short while when it is not there
  /// yet; `null` when it still has not come.
  Future<String?> _addressSoon() async {
    for (var tried = 1; ; tried++) {
      try {
        return await phone.address();
      } on PhoneAddressNotReady {
        if (tried == _addressTries) return null;
        await Future<void>.delayed(addressWait);
      }
    }
  }

  @override
  Future<NotificationStatus> turnOff() async {
    try {
      await registry.forget(await phone.address());
    } on PhoneAddressNotReady {
      // Turned on a moment ago: the server was never given this phone.
    }
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
    } on PhoneAddressNotReady {
      // The address comes through [PhoneNotifications.addressChanges].
    } catch (error, stack) {
      reportError(error, stack, where: 'notification address');
    }
  }

  void dispose() => unawaited(_addressChanges.cancel());
}
