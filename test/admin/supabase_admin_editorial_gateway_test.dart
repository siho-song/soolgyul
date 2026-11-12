import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soolgyul/src/admin/admin_editorial_models.dart';
import 'package:soolgyul/src/admin/data/admin_editorial_gateway.dart';
import 'package:soolgyul/src/admin/data/supabase_admin_editorial_gateway.dart';
import 'package:soolgyul/src/core/errors/error_report.dart';
import 'package:soolgyul/src/features/editorial/data/editorial_article.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<String> reported;
  setUp(() {
    reported = <String>[];
    addTearDown(
      captureErrorReports((error, stack, where) => reported.add(where)),
    );
  });

  group('sign-in', () {
    Future<Object?> signInAnswered(String errorCode) async {
      final gateway = _gateway(
        (request) async =>
            _json(<String, dynamic>{'error_code': errorCode, 'msg': 'no'}, 400),
      );
      try {
        await gateway.signIn(loginId: 'editor', password: 'wrong');
      } catch (error) {
        return error;
      }
      return null;
    }

    test('a wrong id or password is named, not reported', () async {
      final error = await signInAnswered('invalid_credentials');
      expect(
        (error! as AdminEditorialException).message,
        AdminEditorialException.invalidCredentials,
      );
      expect(reported, isEmpty);
    });

    test('another 400 is a plain failure and is reported', () async {
      final error = await signInAnswered('email_not_confirmed');
      expect((error! as AdminEditorialException).message, isNull);
      expect(reported, <String>['admin:signIn']);
    });
  });

  test('a photo whose row is refused is taken back out of Storage', () async {
    final requests = <String>[];
    final gateway = _gateway((request) async {
      requests.add('${request.method} ${request.url.path}');
      final path = request.url.path;
      if (path.startsWith('/storage/v1/object/soolgyul-editorial/')) {
        return _json(<String, dynamic>{'Key': 'k'}, 200);
      }
      if (request.method == 'GET') return _json(<dynamic>[], 200);
      if (request.method == 'POST') {
        return _json(<String, dynamic>{'message': 'denied'}, 403);
      }
      return _json(<dynamic>[], 200);
    });

    await expectLater(
      gateway.uploadMedia(
        const AdminMediaUpload(
          articleId: 'article-1',
          fileName: 'one.jpg',
          mediaType: 'image/jpeg',
          bytes: <int>[1],
        ),
      ),
      throwsA(isA<AdminEditorialException>()),
    );
    expect(requests.sublist(requests.length - 2), <String>[
      'POST /rest/v1/editorial_article_media_assets',
      'DELETE /storage/v1/object/soolgyul-editorial',
    ]);
    expect(reported, <String>['admin:upload']);
  });

  group('deleting a photo', () {
    const media = EditorialMediaAsset(
      id: 'media-1',
      storageBucket: 'soolgyul-editorial',
      storageObjectPath: 'article-1/one.jpg',
      sortOrder: 0,
    );

    test('removes the row first, then the file', () async {
      final requests = <String>[];
      final gateway = _gateway((request) async {
        requests.add('${request.method} ${request.url.path}');
        return request.url.path.startsWith('/rest/')
            ? _json(<dynamic>[
                <String, dynamic>{'id': 'media-1'},
              ], 200)
            : _json(<dynamic>[], 200);
      });

      await gateway.deleteMedia(media);
      expect(requests, <String>[
        'DELETE /rest/v1/editorial_article_media_assets',
        'DELETE /storage/v1/object/soolgyul-editorial',
      ]);
    });

    test('fails and keeps the file when no row was deleted', () async {
      final requests = <String>[];
      final gateway = _gateway((request) async {
        requests.add('${request.method} ${request.url.path}');
        return _json(<dynamic>[], 200);
      });

      await expectLater(
        gateway.deleteMedia(media),
        throwsA(isA<AdminEditorialException>()),
      );
      expect(requests, <String>[
        'DELETE /rest/v1/editorial_article_media_assets',
      ]);
    });
  });
}

SupabaseAdminEditorialGateway _gateway(
  Future<http.Response> Function(http.Request request) respond,
) => SupabaseAdminEditorialGateway(
  SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    // Postgrest reads the request off the response.
    httpClient: MockClient(
      (request) async => _withRequest(await respond(request), request),
    ),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  ),
);

http.Response _withRequest(http.Response response, http.Request request) =>
    http.Response.bytes(
      response.bodyBytes,
      response.statusCode,
      headers: response.headers,
      request: request,
    );

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);
