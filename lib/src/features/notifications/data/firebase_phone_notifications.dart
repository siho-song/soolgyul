import 'package:app_settings/app_settings.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'phone_notification_access.dart';

/// [PhoneNotifications] through Firebase Cloud Messaging.
class FirebasePhoneNotifications implements PhoneNotifications {
  FirebaseMessaging? _started;

  Future<FirebaseMessaging> _messaging() async {
    final started = _started;
    if (started != null) return started;
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    // An iPhone shows nothing while the app is open unless told to.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    return _started = messaging;
  }

  /// An Android phone that refused once still shows its question again;
  /// only after the second refusal are the settings the one way left.
  PhonePermission _read(NotificationSettings settings) =>
      switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PhonePermission.allowed,
        AuthorizationStatus.notDetermined => PhonePermission.notAsked,
        AuthorizationStatus.denied =>
          defaultTargetPlatform == TargetPlatform.android
              ? PhonePermission.notAsked
              : PhonePermission.refused,
        AuthorizationStatus.deniedPermanently => PhonePermission.refused,
      };

  @override
  Future<PhonePermission> permission() async =>
      _read(await (await _messaging()).getNotificationSettings());

  @override
  Future<PhonePermission> ask() async =>
      _read(await (await _messaging()).requestPermission());

  @override
  Future<String> address() async {
    final messaging = await _messaging();
    // An iPhone has no address at Firebase before Apple gave it one.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await messaging.getAPNSToken() == null) {
      throw StateError('the phone has no notification address yet');
    }
    final token = await messaging.getToken();
    if (token == null) {
      throw StateError('the phone has no notification address yet');
    }
    return token;
  }

  @override
  Stream<String> get addressChanges async* {
    yield* (await _messaging()).onTokenRefresh;
  }

  @override
  Future<void> openSettings() =>
      AppSettings.openAppSettings(type: AppSettingsType.notification);
}

/// [PushDeviceRegistry] at Supabase.
class SupabasePushDeviceRegistry implements PushDeviceRegistry {
  SupabasePushDeviceRegistry(this._client);

  final SupabaseClient _client;

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<void> register(String address) => _client.rpc(
    'soolgyul_register_push_device',
    params: <String, Object>{'p_token': address, 'p_platform': _platform},
  );

  @override
  Future<void> forget(String address) => _client.rpc(
    'soolgyul_unregister_push_device',
    params: <String, Object>{'p_token': address},
  );
}
