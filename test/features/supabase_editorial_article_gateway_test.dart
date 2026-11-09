import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/features/editorial/data/supabase_editorial_article_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _rows = <Object?>[
  <String, Object?>{
    'id': '72000000-0000-4000-8000-000000000001',
    'body': '산미는 이런 느낌이에요\n\n레몬처럼 상큼했어요',
    'instagram_url': 'https://www.instagram.com/p/ABC123/',
    'published_at': '2026-08-18T00:00:00Z',
    'media': <Object?>[
      <String, Object?>{
        'id': '73000000-0000-4000-8000-000000000002',
        'storage_bucket': 'editorial-media',
        'storage_object_path': 'articles/acidity/glass.jpg',
        'sort_order': 1,
      },
      <String, Object?>{
        'id': '73000000-0000-4000-8000-000000000001',
        'storage_bucket': 'flutter-assets',
        'storage_object_path':
            'assets/component_assets/explore_feed/beginner_wine_acidity.png',
        'sort_order': 0,
      },
    ],
    'interest_links': <Object?>[
      <String, Object?>{'interest_key': 'wine'},
      <String, Object?>{'interest_key': 'korean_traditional'},
    ],
  },
  <String, Object?>{
    'id': '72000000-0000-4000-8000-000000000002',
    'body': '요즘 내추럴 와인이 주목받는 이유',
    'instagram_url': null,
    'published_at': '2026-08-20T00:00:00Z',
    'media': <Object?>[],
    'interest_links': <Object?>[],
  },
];

void main() {
  late SupabaseClient client;
  late List<http.Request> requests;

  setUp(() {
    requests = [];
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(_rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDown(() => client.dispose());

  test(
    'published posts are read newest first with their photos and interests',
    () async {
      final gateway = SupabaseEditorialArticleGateway(client);

      final articles = await gateway.fetchPublishedArticles();

      final query = requests.single.url;
      expect(query.path, '/rest/v1/editorial_articles');
      expect(query.queryParameters['status'], 'eq.published');
      expect(
        query.queryParameters['select'],
        contains('editorial_article_media_assets'),
      );

      expect(articles.map((a) => a.id), [
        '72000000-0000-4000-8000-000000000002',
        '72000000-0000-4000-8000-000000000001',
      ]);
      final article = articles.last;
      expect(article.body, '산미는 이런 느낌이에요\n\n레몬처럼 상큼했어요');
      expect(article.instagramUrl, 'https://www.instagram.com/p/ABC123/');
      expect(articles.first.instagramUrl, isNull);
      expect(article.publishedAt, DateTime.utc(2026, 8, 18));
      expect(article.interestKeys, ['korean_traditional', 'wine']);

      // Photos sorted by sort_order: the bundled one first and so the cover,
      // then the storage photo with its public URL.
      expect(article.mediaAssets.map((m) => m.sortOrder), [0, 1]);
      final cover = article.coverMedia!;
      expect(cover.isBundledAsset, isTrue);
      expect(cover.publicUrl, isNull);
      final photo = article.mediaAssets.last;
      expect(
        photo.publicUrl,
        'https://example.supabase.co/storage/v1/object/public/editorial-media/articles/acidity/glass.jpg',
      );
      expect(article.gallery.map((m) => m.id), [cover.id, photo.id]);
      expect(articles.first.mediaAssets, isEmpty);
      expect(articles.first.coverMedia, isNull);
      expect(articles.first.interestKeys, isEmpty);
    },
  );
}
