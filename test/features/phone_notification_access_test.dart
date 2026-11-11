import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soolgyul/src/features/notifications/data/notification_access.dart';
import 'package:soolgyul/src/features/notifications/data/phone_notification_access.dart';

class _Phone implements PhoneNotifications {
  PhonePermission state = PhonePermission.notAsked;

  /// What the member answers when the phone asks.
  PhonePermission answer = PhonePermission.allowed;
  String current = 'address-1';
  bool hasAddress = true;
  int asked = 0;
  int settingsOpened = 0;
  final changes = StreamController<String>.broadcast();

  @override
  Future<PhonePermission> permission() async => state;

  @override
  Future<PhonePermission> ask() async {
    asked++;
    return state = answer;
  }

  @override
  Future<String> address() async {
    if (!hasAddress) throw StateError('no address yet');
    return current;
  }

  @override
  Stream<String> get addressChanges => changes.stream;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class _Registry implements PushDeviceRegistry {
  final known = <String>{};
  bool offline = false;

  @override
  Future<void> register(String address) async {
    if (offline) throw StateError('offline');
    known.add(address);
  }

  @override
  Future<void> forget(String address) async {
    if (offline) throw StateError('offline');
    known.remove(address);
  }
}

void main() {
  late _Phone phone;
  late _Registry registry;
  late PhoneNotificationAccess access;
  String? account;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    phone = _Phone();
    registry = _Registry();
    account = 'member-a';
    access = PhoneNotificationAccess(
      phone: phone,
      registry: registry,
      accountId: () => account,
    );
    addTearDown(access.dispose);
  });

  test('is off until the member turns it on', () async {
    expect(await access.load(), NotificationStatus.off);
    expect(phone.asked, 0);
  });

  test('turning on asks the phone and gives the server its address', () async {
    expect(await access.turnOn(), NotificationStatus.on);
    expect(phone.asked, 1);
    expect(registry.known, {'address-1'});
    expect(await access.load(), NotificationStatus.on);
  });

  test('a phone that already allows them is not asked again', () async {
    phone.state = PhonePermission.allowed;
    expect(await access.load(), NotificationStatus.off);
    expect(await access.turnOn(), NotificationStatus.on);
    expect(phone.asked, 0);
  });

  test('a refusal on the phone registers nothing', () async {
    phone.answer = PhonePermission.refused;
    expect(await access.turnOn(), NotificationStatus.blocked);
    expect(registry.known, isEmpty);
    expect(await access.load(), NotificationStatus.blocked);
  });

  test('a question put away without an answer leaves them off', () async {
    phone.answer = PhonePermission.notAsked;
    expect(await access.turnOn(), NotificationStatus.off);
    expect(registry.known, isEmpty);
  });

  test('stays off when the server could not be told', () async {
    registry.offline = true;
    await expectLater(access.turnOn(), throwsStateError);
    registry.offline = false;
    expect(await access.load(), NotificationStatus.off);
  });

  test('turning off makes the server forget the phone', () async {
    await access.turnOn();
    expect(await access.turnOff(), NotificationStatus.off);
    expect(registry.known, isEmpty);
  });

  test('stays on when the server could not be told to forget', () async {
    await access.turnOn();
    registry.offline = true;
    await expectLater(access.turnOff(), throwsStateError);
    registry.offline = false;
    expect(await access.load(), NotificationStatus.on);
    expect(registry.known, {'address-1'});
  });

  test('notifications turned off in the phone\'s settings read as blocked, '
      'and come back on when allowed again', () async {
    await access.turnOn();
    phone.state = PhonePermission.refused;
    expect(await access.load(), NotificationStatus.blocked);
    phone.state = PhonePermission.allowed;
    expect(await access.load(), NotificationStatus.on);
  });

  test('each account on the phone has its own choice', () async {
    await access.turnOn();
    account = 'member-b';
    expect(await access.load(), NotificationStatus.off);
    account = null;
    expect(await access.load(), NotificationStatus.off);
  });

  test('signing out makes the server forget the phone, signing in again '
      'brings it back', () async {
    await access.turnOn();
    await access.forgetThisPhone();
    expect(registry.known, isEmpty);
    expect(await access.load(), NotificationStatus.on);

    await access.resume();
    expect(registry.known, {'address-1'});
  });

  test('signing out never fails, whatever the server says', () async {
    await access.turnOn();
    registry.offline = true;
    await access.forgetThisPhone();
    phone.hasAddress = false;
    await access.forgetThisPhone();
  });

  test('arriving registers nothing for a member who has them off', () async {
    await access.resume();
    expect(registry.known, isEmpty);

    await access.turnOn();
    await access.turnOff();
    await access.resume();
    expect(registry.known, isEmpty);
  });

  test('a changed address reaches the server only while they are on', () async {
    phone.changes.add('address-0');
    await pumpEventQueue();
    expect(registry.known, isEmpty);

    await access.turnOn();
    phone.changes.add('address-2');
    await pumpEventQueue();
    expect(registry.known, {'address-1', 'address-2'});
  });

  test('opens the phone\'s settings', () async {
    await access.openPhoneSettings();
    expect(phone.settingsOpened, 1);
  });
}
