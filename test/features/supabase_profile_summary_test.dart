import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soolgyul/src/features/profile/data/supabase_profile_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_supabase.dart';

void main() {
  test(
    'authenticated summary sends owner filters and exact count joins',
    () async {
      final requests = <http.Request>[];
      final client = fakeSupabaseClient((request) async {
        requests.add(request);
        final records = request.url.path.endsWith('/drink_records');
        final count = records
            ? 37
            : request.url.path.endsWith('/user_saved_articles')
            ? 12
            : request.url.path.endsWith('/user_saved_drinks')
            ? 5
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
      });
      addTearDown(client.dispose);
      await signInFake(client);
      final summary = await SupabaseProfileSummary(client).load();
      expect(summary.cardCount, 37);
      expect(summary.savedArticleCount, 12);
      expect(summary.likedCardCount, 8);
      expect(summary.savedDrinkCount, 5);
      expect(requests, hasLength(4));
      for (final request in requests) {
        expect(request.url.queryParameters['user_id'], 'eq.user-1');
        expect(request.headers['Prefer'], contains('count=exact'));
      }
      expect(
        requests[1].url.queryParameters['editorial_articles.status'],
        'eq.published',
      );
      expect(
        requests[2].url.queryParameters['drink_records.user_id'],
        'eq.user-1',
      );
    },
  );

  test('missing session fails instead of claiming zero records', () async {
    final client = SupabaseClient('https://example.supabase.co', 'test-key');
    addTearDown(client.dispose);
    await expectLater(SupabaseProfileSummary(client).load(), throwsStateError);
  });
}
