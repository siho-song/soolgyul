import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/features/profile/data/supabase_liked_cards_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late SupabaseLikedCardsGateway gateway;
  late List<http.Request> requests;
  var failDelete = false;
  late Set<String> liked;
  String? recordCategory = 'wine';

  setUp(() async {
    requests = [];
    liked = {};
    failDelete = false;
    recordCategory = 'wine';
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
                'id': 'owner',
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
        if (request.method == 'POST' &&
            request.url.path.endsWith('/user_liked_drink_cards')) {
          liked.add(
            (jsonDecode(request.body) as Map)['drink_record_id'] as String,
          );
          return http.Response('', 201, request: request);
        }
        if (request.url.queryParameters['select'] == 'drink_record_id') {
          final id = request.url.queryParameters['drink_record_id']!.substring(
            3,
          );
          return http.Response(
            jsonEncode([
              if (liked.contains(id)) {'drink_record_id': id},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'DELETE') {
          return http.Response(
            failDelete ? '{"message":"denied","code":"42501"}' : '',
            failDelete ? 403 : 204,
            request: request,
          );
        }
        if (request.url.path.endsWith(
          '/soolgyul_catalog_primary_media_rows_v1',
        )) {
          return http.Response(
            jsonEncode([
              {'alcohol_item_id': 'item', 'media_path': 'product.webp'},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/soolgyul_my_liked_cards')) {
          return http.Response(
            jsonEncode({
              'total': 42,
              'cards': [
                for (final id in ['a', 'b'])
                  {
                    'drink_record_id': id,
                    'liked_at': '2026-09-20T00:00:00Z',
                    'recorded_at': '2026-09-01T00:00:00Z',
                    'note': id == 'a' ? '내 메모' : null,
                    'result_id': 'card-$id',
                    'brief': id == 'a' ? '산미가 반가웠어요.' : null,
                    'summary': '**산미**가 반가웠어요.',
                    'alcohol_item_id': id == 'a'
                        ? 'item'
                        : 'item-without-photo',
                    'name': id == 'a' ? '카탈로그 이름' : '사진 없는 술',
                    'interest_key': id == 'a' ? recordCategory : null,
                  },
              ],
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 404, request: request);
      }),
    );
    await client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-password',
    );
    gateway = SupabaseLikedCardsGateway(client);
  });
  tearDown(() => client.dispose());

  test(
    'like confirms saved state and repeated requests ignore duplicates',
    () async {
      expect(await gateway.isLiked('a'), isFalse);
      await gateway.like('a');
      await gateway.like('a');
      expect(await gateway.isLiked('a'), isTrue);
      expect(liked, {'a'});
      for (final request in requests.where((r) => r.method == 'POST')) {
        expect(jsonDecode(request.body), {
          'user_id': 'owner',
          'drink_record_id': 'a',
        });
        expect(
          request.headers['Prefer'],
          contains('resolution=ignore-duplicates'),
        );
      }
    },
  );

  test(
    'list reads one page through the owner RPC and public batch images',
    () async {
      final result = await gateway.fetch(
        category: 'wine',
        latestFirst: false,
        offset: 30,
      );
      expect(result.total, 42);
      expect(result.cards.map((row) => row.id), ['a', 'b']);
      expect(result.cards.first.title, '카탈로그 이름');
      expect(result.cards.first.category, 'wine');
      expect(result.cards.first.resultId, 'card-a');
      expect(result.cards.first.summary, '산미가 반가웠어요.');
      expect(result.cards.first.note, '내 메모');
      expect(result.cards.first.likedAt, DateTime.utc(2026, 9, 20).toLocal());
      expect(result.cards.last.title, '사진 없는 술');
      expect(
        result.cards.first.imageUrl,
        contains('/alcohol-product-images/product.webp'),
      );
      expect(result.cards.last.imageUrl, isNull);
      expect(
        result.cards.last.summary,
        '산미가 반가웠어요.',
        reason: 'a card made before the brief lends its line without marks',
      );
      expect(result.cards.last.note, isNull);
      expect(requests, hasLength(2));
      final call = requests.first;
      expect(call.method, 'POST');
      expect(call.url.path, '/rest/v1/rpc/soolgyul_my_liked_cards');
      expect(jsonDecode(call.body), {
        'p_category': 'wine',
        'p_latest_first': false,
        'p_offset': 30,
        'p_limit': 30,
      });
      expect(
        requests.last.url.path,
        '/rest/v1/rpc/soolgyul_catalog_primary_media_rows_v1',
      );
    },
  );

  test(
    'the unfiltered list keeps records without a category as other',
    () async {
      final result = await gateway.fetch();
      expect(jsonDecode(requests.first.body), {
        'p_category': null,
        'p_latest_first': true,
        'p_offset': 0,
        'p_limit': 30,
      });
      expect(result.cards.last.category, 'other');
      expect(result.cards.last.imageUrl, isNull);
    },
  );

  test('interest filters pass the interest key to the RPC', () async {
    recordCategory = 'sake';
    final result = await gateway.fetch(category: 'sake');
    expect(result.cards.first.category, 'sake');
    expect(jsonDecode(requests.first.body)['p_category'], 'sake');
  });

  test(
    'unlike only deletes the owner-card relationship and is repeatable',
    () async {
      await gateway.unlike('a');
      await gateway.unlike('a');
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/rest/v1/user_liked_drink_cards');
        expect(request.url.queryParameters, {
          'user_id': 'eq.owner',
          'drink_record_id': 'eq.a',
        });
      }
    },
  );

  test(
    'server rejection propagates instead of claiming unlike success',
    () async {
      failDelete = true;
      await expectLater(
        gateway.unlike('a'),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test('signed out requests never reach the database', () async {
    await client.auth.signOut(scope: SignOutScope.local);
    requests.clear();
    await expectLater(gateway.fetch(), throwsStateError);
    await expectLater(gateway.unlike('a'), throwsStateError);
    expect(requests, isEmpty);
  });
}
