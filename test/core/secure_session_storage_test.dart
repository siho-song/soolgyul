import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/core/secure_session_storage.dart';

void main() {
  const key = 'sb-project-auth-token';
  const storage = SecureSessionStorage(persistSessionKey: key);

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('nothing is kept before a sign-in', () async {
    await storage.initialize();

    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
  });

  test('a persisted session is read back from secure storage', () async {
    await storage.persistSession('{"refresh_token":"r1"}');

    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), '{"refresh_token":"r1"}');
    expect(
      await const FlutterSecureStorage().read(key: key),
      '{"refresh_token":"r1"}',
    );
  });

  test('a session kept by an earlier launch is found', () async {
    FlutterSecureStorage.setMockInitialValues({key: 'earlier'});

    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), 'earlier');
  });

  test('a removed session is gone', () async {
    await storage.persistSession('session');
    await storage.removePersistedSession();

    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
  });

  test('each project keeps its session under its own key', () {
    final storage = SecureSessionStorage.forProject(
      'https://abcdefgh.supabase.co',
    );

    expect(storage.persistSessionKey, 'sb-abcdefgh-auth-token');
  });

  test('the PKCE verifier is kept, read back and removed', () async {
    const pkce = SecurePkceStorage();

    await pkce.setItem(key: 'verifier', value: 'v1');
    expect(await pkce.getItem(key: 'verifier'), 'v1');

    await pkce.removeItem(key: 'verifier');
    expect(await pkce.getItem(key: 'verifier'), isNull);
  });
}
