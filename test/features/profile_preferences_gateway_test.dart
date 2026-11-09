import 'package:flutter_test/flutter_test.dart';
import 'package:soolgyul/src/features/profile/data/profile_preferences_gateway.dart';
import 'package:soolgyul/src/features/profile/data/supabase_profile_preferences_gateway.dart';
import 'package:soolgyul/src/features/profile/profile_setup_draft.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'test-anon-key');
  });

  tearDown(() async {
    await client.dispose();
  });

  test('fetch parses the profile RPC response into typed interests', () async {
    final calls = <_RpcCall>[];
    final gateway = SupabaseProfilePreferencesGateway(
      client,
      rpcInvoker: (functionName, parameters) async {
        calls.add(_RpcCall(functionName, parameters));
        return <String, dynamic>{
          'display_name': '서버민지',
          'interest_group_keys': <String>['wine', 'sake', 'whisky'],
        };
      },
    );

    final preferences = await gateway.fetchProfilePreferences();

    expect(preferences.displayName, '서버민지');
    expect(preferences.interests, <DrinkInterest>{
      DrinkInterest.wine,
      DrinkInterest.sake,
      DrinkInterest.whisky,
    });
    expect(calls.single.functionName, 'soolgyul_get_my_profile_preferences');
    expect(calls.single.parameters, isEmpty);
  });

  test('mutations send stable wire keys and a new idempotency UUID', () async {
    final calls = <_RpcCall>[];
    final idempotencyKeys = <String>[
      '10000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002',
    ].iterator;
    final gateway = SupabaseProfilePreferencesGateway(
      client,
      idempotencyKeyFactory: () {
        idempotencyKeys.moveNext();
        return idempotencyKeys.current;
      },
      rpcInvoker: (functionName, parameters) async {
        calls.add(_RpcCall(functionName, parameters));
        return switch (functionName) {
          'soolgyul_update_my_display_name' => <String, dynamic>{
            'display_name': '정규화닉네임',
          },
          'soolgyul_replace_my_drink_interests' => <String, dynamic>{
            'interest_group_keys': <String>['wine', 'sake', 'whisky'],
          },
          _ => throw StateError(functionName),
        };
      },
    );

    expect(await gateway.updateDisplayName(' 새닉네임 '), '정규화닉네임');
    expect(
      await gateway.replaceDrinkInterests(<DrinkInterest>{
        DrinkInterest.whisky,
        DrinkInterest.sake,
        DrinkInterest.wine,
      }),
      <DrinkInterest>{
        DrinkInterest.wine,
        DrinkInterest.sake,
        DrinkInterest.whisky,
      },
    );

    expect(calls[0].functionName, 'soolgyul_update_my_display_name');
    expect(calls[0].parameters, <String, dynamic>{
      'p_display_name': ' 새닉네임 ',
      'p_idempotency_key': '10000000-0000-4000-8000-000000000001',
    });
    expect(calls[1].functionName, 'soolgyul_replace_my_drink_interests');
    expect(calls[1].parameters, <String, dynamic>{
      'p_interest_group_keys': <String>['wine', 'whisky', 'sake'],
      'p_idempotency_key': '10000000-0000-4000-8000-000000000002',
    });
  });

  test('malformed and unknown server values fail closed', () async {
    final gateway = SupabaseProfilePreferencesGateway(
      client,
      rpcInvoker: (_, _) async => <String, dynamic>{
        'display_name': '민지',
        'interest_group_keys': <String>['wine', 'unknown_group'],
      },
    );

    await expectLater(
      gateway.fetchProfilePreferences(),
      throwsA(
        isA<ProfilePreferencesException>().having(
          (error) => error.operation,
          'operation',
          ProfilePreferencesOperation.fetch,
        ),
      ),
    );
  });

  test(
    'default mutation idempotency keys are RFC 4122 UUID v4 values',
    () async {
      String? idempotencyKey;
      final gateway = SupabaseProfilePreferencesGateway(
        client,
        rpcInvoker: (_, parameters) async {
          idempotencyKey = parameters['p_idempotency_key'] as String?;
          return <String, dynamic>{'display_name': '민지'};
        },
      );

      await gateway.updateDisplayName('민지');

      expect(
        idempotencyKey,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
            r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    },
  );
}

class _RpcCall {
  const _RpcCall(this.functionName, this.parameters);

  final String functionName;
  final Map<String, dynamic> parameters;
}
