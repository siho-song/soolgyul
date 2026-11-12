import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/features/profile/data/account_deletion_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_supabase.dart';

const _statePath = '/rest/v1/rpc/soolgyul_get_my_deletion_state';
const _functionPath = '/functions/v1/account-deletion';

http.Response _json(http.Request request, Object? body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );

const _active = <String, Object?>{
  'deletion_state': 'active',
  'scheduled_deletion_at': null,
  'restore_available': false,
  'provider_revoked': false,
};

const _scheduled = <String, Object?>{
  'deletion_state': 'scheduled',
  'scheduled_deletion_at': '2026-12-13T00:00:00Z',
  'restore_available': true,
  'provider_revoked': false,
};

void main() {
  late List<http.Request> requests;
  late Map<String, dynamic> state;
  late http.Response Function(http.Request request) functionReply;
  late int proofLoads;

  setUp(() {
    requests = <http.Request>[];
    state = Map<String, dynamic>.of(_active);
    functionReply = (request) => _json(request, _scheduled);
    proofLoads = 0;
  });

  SupabaseAccountDeletionGateway gatewayFor(SupabaseClient client) =>
      SupabaseAccountDeletionGateway(
        client,
        loadProviderProof: () async {
          proofLoads += 1;
          return <String, dynamic>{'provider': 'kakao', 'token': 'proof'};
        },
      );

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    return switch (request.url.path) {
      _statePath => _json(request, state),
      _functionPath => functionReply(request),
      _ => _json(request, <String, Object?>{}, 404),
    };
  }

  /// A signed-in client whose server answers through [respond].
  Future<SupabaseClient> signedInClient() async {
    final client = fakeSupabaseClient(respond);
    addTearDown(client.dispose);
    await signInFake(client);
    return client;
  }

  group('fetchStatus', () {
    test('reads the state straight from the database', () async {
      state = Map<String, dynamic>.of(_scheduled);
      final gateway = gatewayFor(await signedInClient());

      final status = await gateway.fetchStatus();

      expect(requests.single.url.path, _statePath);
      expect(status.state, 'scheduled');
      expect(status.deadline, DateTime.utc(2026, 12, 13));
      expect(status.canRestore, isTrue);
      expect(status.providerRevoked, isFalse);
    });

    test('a state without a deadline has none', () async {
      final gateway = gatewayFor(await signedInClient());

      final status = await gateway.fetchStatus();

      expect(status.state, 'active');
      expect(status.deadline, isNull);
      expect(status.canRestore, isFalse);
    });

    test('a refused read says the state could not be checked', () async {
      final client = fakeSupabaseClient((request) async {
        return _json(request, <String, Object?>{'message': 'boom'}, 500);
      });
      addTearDown(client.dispose);

      await expectLater(
        gatewayFor(client).fetchStatus(),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.message,
            'message',
            '계정 상태를 확인하지 못했어요. 다시 시도해 주세요.',
          ),
        ),
      );
    });
  });

  group('requestDeletion', () {
    test('sends the provider proof, then signs this phone out', () async {
      final client = await signedInClient();
      final gateway = gatewayFor(client);
      expect(client.auth.currentSession, isNotNull);

      await gateway.requestDeletion();

      final call = requests.singleWhere((r) => r.url.path == _functionPath);
      expect(call.method, 'POST');
      expect(jsonDecode(call.body), <String, Object?>{
        'action': 'request',
        'confirmed': true,
        'proof': <String, Object?>{'provider': 'kakao', 'token': 'proof'},
      });
      expect(proofLoads, 1);
      expect(client.auth.currentSession, isNull);
    });

    test('a provider already revoked is not asked for proof again', () async {
      state = <String, dynamic>{..._active, 'provider_revoked': true};
      final gateway = gatewayFor(await signedInClient());

      await gateway.requestDeletion();

      final call = requests.singleWhere((r) => r.url.path == _functionPath);
      expect(jsonDecode(call.body)['proof'], <String, Object?>{});
      expect(proofLoads, 0);
    });

    test('a purged account is refused before the server is asked', () async {
      state = <String, dynamic>{..._active, 'deletion_state': 'purged'};
      final client = await signedInClient();

      await expectLater(
        gatewayFor(client).requestDeletion(),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.message,
            'message',
            '이미 삭제가 완료된 계정이에요.',
          ),
        ),
      );
      expect(requests.where((r) => r.url.path == _functionPath), isEmpty);
      expect(client.auth.currentSession, isNotNull);
    });

    test('a failed sign-out of this phone keeps the withdrawal', () async {
      // The server has already ended every session, and refuses the
      // phone's own sign-out with something other than "no session".
      final signedIn = await signedInClient();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/v1/logout')) {
            return _json(request, <String, Object?>{
              'message': 'unavailable',
            }, 503);
          }
          return respond(request);
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(
        jsonEncode(signedIn.auth.currentSession!.toJson()),
      );
      expect(client.auth.currentSession, isNotNull);

      await gatewayFor(client).requestDeletion();

      expect(requests.where((r) => r.url.path == _functionPath), hasLength(1));
      expect(client.auth.currentSession, isNull);
    });

    test('each refusal of the server reads as its own message', () async {
      const messages = <String?, String>{
        'restore_window_closed': '계정 복구 가능 기간이 만료되었어요.',
        'account_restore_unavailable': '계정 복구 가능 기간이 만료되었어요.',
        'provider_configuration_missing': '소셜 계정 연동 해제에 실패했어요. 고객센터로 문의해 주세요.',
        'provider_identity_mismatch': '현재 로그인된 소셜 계정과 일치하지 않아요.',
        'linked_provider_review_required':
            '복수의 소셜 계정이 연결되어 있어 자동 탈퇴가 어려워요. 1:1 문의를 이용해 주세요.',
        'provider_reauthentication_required': '본인 확인을 위해 소셜 로그인을 다시 진행해 주세요.',
        'provider_verification_failed': '본인 확인을 위해 소셜 로그인을 다시 진행해 주세요.',
        'something_else': '탈퇴 처리를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
        null: '탈퇴 처리를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
      };
      final gateway = gatewayFor(await signedInClient());
      for (final MapEntry(key: code, value: message) in messages.entries) {
        functionReply = (request) =>
            _json(request, <String, Object?>{'error_code': ?code}, 409);
        await expectLater(
          gateway.requestDeletion(),
          throwsA(
            isA<AccountDeletionException>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
          reason: '$code',
        );
      }
    });
  });

  test('restore asks the server function to restore', () async {
    final gateway = gatewayFor(await signedInClient());

    await gateway.restore();

    final call = requests.single;
    expect(call.url.path, _functionPath);
    expect(jsonDecode(call.body), <String, Object?>{'action': 'restore'});
  });
}
