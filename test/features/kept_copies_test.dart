import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/features/editorial/data/supabase_editorial_article_gateway.dart';
import 'package:soolgyul/src/features/home/data/supabase_taste_letters_gateway.dart';
import 'package:soolgyul/src/features/preferences/data/supabase_preference_history_gateway.dart';
import 'package:soolgyul/src/features/profile/data/profile_setup_draft.dart';
import 'package:soolgyul/src/features/profile/data/supabase_profile_preferences_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/memory_saved_views.dart';

// Each gateway keeps the server's answer on the phone as it loads it, and
// gives the same thing back from the phone without asking the server.

const _letterRows = <Object?>[
  <String, Object?>{
    'axes': <String, Object?>{},
    'record_count': 3,
    'updated_at': '2026-10-03T00:00:00Z',
  },
];
const _changeRows = <Object?>[
  <String, Object?>{
    'axis': 'aroma',
    'from_letter': null,
    'to_letter': 'F',
    'left_share': 100,
    'right_share': 0,
    'product_name': '테스트 술',
    'changed_at': '2026-10-01T00:00:00Z',
    'drink_records': <String, Object?>{
      'taste_cards': <String, Object?>{'id': 'card-1'},
    },
  },
];
const _historyRows = <Object?>[
  <String, Object?>{
    'result_id': 'card-1',
    'recorded_at': '2026-10-01T03:00:00Z',
    'alcohol_item_id': 'item-1',
    'name': '발베니 더블우드 12년',
    'category_key': 'whisky',
    'category_label': '위스키',
    'media_path': 'whisky/item-1.webp',
    'note': '부드러웠어요',
    'summary': '**바닐라**가 좋았어요.',
    'brief': '바닐라가 좋았어요.',
    'tags': <Object?>[
      <String, Object?>{'label': '바닐라', 'kind': 'liked'},
    ],
  },
];
const _postRows = <Object?>[
  <String, Object?>{
    'id': '72000000-0000-4000-8000-000000000001',
    'body': '산미는 이런 느낌이에요',
    'instagram_url': null,
    'published_at': '2026-08-18T00:00:00Z',
    'media': <Object?>[],
    'interest_links': <Object?>[
      <String, Object?>{'interest_key': 'wine'},
    ],
  },
];

void main() {
  late SupabaseClient client;
  late MemorySavedViews phone;
  late int serverCalls;

  setUp(() async {
    serverCalls = 0;
    phone = MemorySavedViews(account: 'user-1');
    client = SupabaseClient(
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
        serverCalls += 1;
        final path = request.url.path;
        final Object body = switch (path) {
          _ when path.endsWith('/taste_letters') => _letterRows,
          _ when path.endsWith('/taste_letter_changes') => _changeRows,
          _ when path.endsWith('/soolgyul_my_drink_history') => _historyRows,
          _ when path.endsWith('/drink_records') => <Object?>[
            <String, Object?>{'created_at': '2026-10-01T03:00:00Z'},
          ],
          _ when path.endsWith('/editorial_articles') => _postRows,
          _ => <Object?>[],
        };
        return http.Response(
          jsonEncode(body),
          200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-password',
    );
  });
  tearDown(() => client.dispose());

  /// Lets the unawaited write behind a load finish.
  Future<void> written() => Future<void>.delayed(Duration.zero);

  test(
    'the letters come back from the phone as the server gave them',
    () async {
      expect(
        await SupabaseTasteLettersGateway(client, saved: phone).kept(),
        isNull,
      );

      final loaded = await SupabaseTasteLettersGateway(
        client,
        saved: phone,
      ).load();
      await written();
      final asked = serverCalls;
      final kept = await SupabaseTasteLettersGateway(
        client,
        saved: phone,
      ).kept();

      expect(serverCalls, asked, reason: 'the copy is read without the server');
      expect(kept?.state?.recordCount, loaded.state?.recordCount);
      expect(kept?.changes.single.resultId, 'card-1');
      expect(kept?.changes.single.toLetter, loaded.changes.single.toLetter);
    },
  );

  test(
    'a month of records and the newest date come back from the phone',
    () async {
      final month = DateTime(2026, 10);
      final gateway = SupabasePreferenceHistoryGateway(client, saved: phone);
      expect(await gateway.keptMonth(month), isNull);
      expect(await gateway.keptLatest(), isNull);

      final loaded = await gateway.loadMonth(month);
      final latest = await gateway.latestRecordedAt();
      await written();
      final asked = serverCalls;
      final again = SupabasePreferenceHistoryGateway(client, saved: phone);
      final kept = await again.keptMonth(month);

      expect(serverCalls, asked);
      expect(kept?.single.resultId, loaded.single.resultId);
      expect(kept?.single.title, '발베니 더블우드 12년');
      expect(kept?.single.imageUrl, loaded.single.imageUrl);
      expect(kept?.single.note, '부드러웠어요');
      expect(await again.keptLatest(), latest);
      expect(await again.keptMonth(DateTime(2026, 9)), isNull);
    },
  );

  test('the posts come back from the phone', () async {
    final loaded = await SupabaseEditorialArticleGateway(
      client,
      saved: phone,
    ).fetchPublishedArticles();
    await written();
    final asked = serverCalls;
    final kept = await SupabaseEditorialArticleGateway(
      client,
      saved: phone,
    ).kept();

    expect(serverCalls, asked);
    expect(kept?.single.id, loaded.single.id);
    expect(kept?.single.body, '산미는 이런 느낌이에요');
    expect(kept?.single.interestKeys, <String>['wine']);
  });

  test('the profile comes back from the phone', () async {
    SupabaseProfilePreferencesGateway gateway() =>
        SupabaseProfilePreferencesGateway(
          client,
          saved: phone,
          rpcInvoker: (_, _) async {
            serverCalls += 1;
            return <String, dynamic>{
              'display_name': '민지',
              'interest_group_keys': <String>['wine', 'sake'],
              'gender': 'female',
            };
          },
        );
    expect(await gateway().kept(), isNull);

    await gateway().fetchProfilePreferences();
    await written();
    final asked = serverCalls;
    final kept = await gateway().kept();

    expect(serverCalls, asked);
    expect(kept?.displayName, '민지');
    expect(kept?.interests, <DrinkInterest>{
      DrinkInterest.wine,
      DrinkInterest.sake,
    });
  });

  test('another account on the same phone gets none of it', () async {
    await SupabaseTasteLettersGateway(client, saved: phone).load();
    await written();

    phone.account = 'user-2';
    expect(
      await SupabaseTasteLettersGateway(client, saved: phone).kept(),
      isNull,
    );
  });
}
