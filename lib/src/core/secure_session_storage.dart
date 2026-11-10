import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// The session holds a long-lived refresh token, so on a phone it lives in the
// Keychain / Keystore-encrypted storage instead of plain preferences.
const _secureStorage = FlutterSecureStorage(
  // Readable after the first unlock so a background start still finds the
  // session, and bound to this device so it never travels in a backup.
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  // The package defaults (RSA-OAEP wrapped AES-GCM) are its recommended setup;
  // a store whose key was lost is reset instead of failing every read.
  aOptions: AndroidOptions(),
);

/// Keeps the Supabase session in the platform's secure storage.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage({required this.persistSessionKey});

  /// Same key shape as the package default, so each project has its own slot.
  factory SecureSessionStorage.forProject(String supabaseUrl) {
    final project = Uri.parse(supabaseUrl).host.split('.').first;
    return SecureSessionStorage(persistSessionKey: 'sb-$project-auth-token');
  }

  final String persistSessionKey;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() async {
    try {
      return await _secureStorage.read(key: persistSessionKey);
    } on PlatformException {
      // Supabase reads this during startup without a guard. Storage that
      // cannot be read right now (a locked phone before its first unlock)
      // means signed out for this launch, not an app that fails to start.
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() =>
      _secureStorage.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secureStorage.write(key: persistSessionKey, value: persistSessionString);
}

/// Keeps the PKCE code verifier of a sign-in in progress beside the session.
class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage();

  @override
  Future<String?> getItem({required String key}) =>
      _secureStorage.read(key: key);

  @override
  Future<void> setItem({required String key, required String value}) =>
      _secureStorage.write(key: key, value: value);

  @override
  Future<void> removeItem({required String key}) =>
      _secureStorage.delete(key: key);
}
