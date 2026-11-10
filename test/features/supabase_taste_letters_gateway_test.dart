import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/features/home/data/supabase_taste_letters_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> _change(String changedAt, Object? record) =>
    <String, Object?>{
      'axis': 'aroma',
      'from_letter': null,
      'to_letter': 'F',
      'left_share': 100,
      'right_share': 0,
      'product_name': '테스트 술',
      'changed_at': changedAt,
      'drink_records': record,
    };

void main() {
  late List<http.Request> requests;
  late List<Object?> letterRows;

  Future<SupabaseClient> signedInClient() async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(
            jsonEncode({
              'access_token': 'test-token',
              'refresh_token': 'test-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': 'user-1',
                'aud': 'authenticated',
                'created_at': '2026-09-01T00:00:00Z',
                'app_metadata': <String, dynamic>{},
                'user_metadata': <String, dynamic>{},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(request);
        final rows = request.url.path.endsWith('/taste_letters')
            ? letterRows
            : <Object?>[
                // One card per record comes as an object, or a list of one.
                _change('2026-10-01T00:00:00Z', <String, Object?>{
                  'taste_cards': <String, Object?>{'id': 'card-1'},
                }),
                _change('2026-10-02T00:00:00Z', <String, Object?>{
                  'taste_cards': <Object?>[
                    <String, Object?>{'id': 'card-2'},
                  ],
                }),
                // A deleted record is hidden by its row policy.
                _change('2026-10-03T00:00:00Z', null),
              ];
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-password',
    );
    return client;
  }

  setUp(() {
    requests = <http.Request>[];
    letterRows = <Object?>[
      <String, Object?>{
        'axes': <String, Object?>{},
        'record_count': 3,
        'updated_at': '2026-10-03T00:00:00Z',
      },
    ];
  });

  test(
    'letters and their changes come from two reads, cards included',
    () async {
      final snapshot = await SupabaseTasteLettersGateway(
        await signedInClient(),
      ).load();

      expect(requests.map((request) => request.url.path).toSet(), <String>{
        '/rest/v1/taste_letters',
        '/rest/v1/taste_letter_changes',
      });
      expect(requests, hasLength(2));
      final changes = requests.firstWhere(
        (request) => request.url.path.endsWith('/taste_letter_changes'),
      );
      expect(
        changes.url.queryParameters['select'],
        contains('drink_records(taste_cards(id))'),
      );
      expect(changes.url.queryParameters['user_id'], 'eq.user-1');
      expect(snapshot.state?.recordCount, 3);
      expect(snapshot.changes.map((change) => change.resultId), <String?>[
        'card-1',
        'card-2',
        null,
      ]);
    },
  );

  test('an account without letters shows none', () async {
    letterRows = <Object?>[];

    final snapshot = await SupabaseTasteLettersGateway(
      await signedInClient(),
    ).load();

    expect(snapshot.state, isNull);
    expect(snapshot.changes, isEmpty);
  });
}
