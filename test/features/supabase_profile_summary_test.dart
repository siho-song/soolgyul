import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/features/profile/data/supabase_profile_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'authenticated summary sends owner filters and exact count joins',
    () async {
      final requests = <http.Request>[];
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
          final records = request.url.path.endsWith('/drink_records');
          final count = records
              ? 37
              : request.url.path.endsWith('/user_saved_articles')
              ? 12
              : 8;
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              'content-range': '*/$count',
            },
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'test@example.com',
        password: 'test-password',
      );
      final summary = await SupabaseProfileSummary(client).load();
      expect(summary.cardCount, 37);
      expect(summary.savedArticleCount, 12);
      expect(summary.likedCardCount, 8);
      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(request.url.queryParameters['user_id'], 'eq.user-1');
        expect(request.headers['Prefer'], contains('count=exact'));
      }
      expect(requests.first.url.queryParameters['deleted_at'], 'is.null');
      expect(
        requests[1].url.queryParameters['editorial_articles.status'],
        'eq.published',
      );
      expect(
        requests[2].url.queryParameters['drink_records.deleted_at'],
        'is.null',
      );
    },
  );

  test('missing session fails instead of claiming zero records', () async {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    addTearDown(client.dispose);
    await expectLater(SupabaseProfileSummary(client).load(), throwsStateError);
  });
}
