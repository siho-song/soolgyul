import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soolgyul/src/features/profile/data/support_inquiry_gateway.dart';
import 'package:soolgyul/src/features/profile/data/supabase_support_inquiry_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const owner = '10000000-0000-0000-0000-000000000001';
const requestId = '20000000-0000-0000-0000-000000000001';
XFile png() => XFile.fromData(
  Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]),
  name: 'image.png',
);
SupportInquiryDraft draft({
  List<XFile> images = const [],
  String content = ' 문의 내용 ',
}) => SupportInquiryDraft(
  id: requestId,
  type: '시스템 오류 및 버그',
  email: ' user@example.com ',
  content: content,
  images: images,
);

void main() {
  late SupabaseClient client;
  late SupabaseSupportInquiryGateway gateway;
  late List<http.Request> requests;
  var uploadFails = false;
  var rpcFails = false;
  var rateLimited = false;
  setUp(() async {
    requests = [];
    uploadFails = rpcFails = rateLimited = false;
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
                'id': owner,
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
        if (request.url.path.contains('/storage/')) {
          return http.Response(
            jsonEncode(
              uploadFails
                  ? {
                      'message': 'upload denied',
                      'statusCode': '403',
                      'error': 'Forbidden',
                    }
                  : {'Key': request.url.path, 'Id': 'file-id'},
            ),
            uploadFails ? 403 : 200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(
            rpcFails
                ? {
                    'message': rateLimited ? 'inquiry_rate_limited' : 'failed',
                    'code': 'P0001',
                  }
                : requestId,
          ),
          rpcFails ? 400 : 200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-password',
    );
    gateway = SupabaseSupportInquiryGateway(client);
  });
  tearDown(() => client.dispose());

  test(
    'text-only submits typed fields without a storage request or client user ID',
    () async {
      await gateway.submit(draft());
      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/soolgyul_submit_support_inquiry',
      );
      expect(jsonDecode(requests.single.body), {
        'p_id': requestId,
        'p_inquiry_type': 'bug',
        'p_reply_email': 'user@example.com',
        'p_content': '문의 내용',
        'p_attachment_paths': [],
      });
    },
  );

  test(
    'uploads actual bytes privately before submitting their paths',
    () async {
      await gateway.submit(draft(images: [png()]));
      expect(requests, hasLength(2));
      expect(
        requests.first.url.path,
        startsWith(
          '/storage/v1/object/soolgyul-private/$owner/inquiries/$requestId/0-',
        ),
      );
      expect(requests.first.headers['x-upsert'], 'true');
      final parameters = jsonDecode(requests.last.body) as Map;
      final path = (parameters['p_attachment_paths'] as List).single as String;
      expect(path, startsWith('$owner/inquiries/$requestId/0-'));
      expect(path, endsWith('.png'));
      expect(path, isNot(contains('http')));
    },
  );

  test(
    'retry keeps the request ID and image paths and does not delete ambiguous uploads',
    () async {
      rpcFails = true;
      await expectLater(
        gateway.submit(draft(images: [png()])),
        throwsA(isA<SupportInquiryException>()),
      );
      final firstPayload = requests.last.body;
      rpcFails = false;
      await gateway.submit(draft(images: [png()]));
      expect(requests.last.body, firstPayload);
      expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
    },
  );

  test('upload failure never submits an incomplete inquiry', () async {
    uploadFails = true;
    await expectLater(
      gateway.submit(draft(images: [png()])),
      throwsA(isA<SupportInquiryException>()),
    );
    expect(requests.every((r) => r.url.path.contains('/storage/')), isTrue);
  });

  test('unsupported images and files over 10MB are rejected', () async {
    for (final file in [
      XFile.fromData(
        Uint8List.fromList(utf8.encode('<html>not an image</html>')),
        name: 'fake.png',
      ),
      XFile.fromData(
        Uint8List(SupabaseSupportInquiryGateway.maxImageBytes + 1),
        name: 'large.png',
      ),
    ]) {
      await expectLater(
        gateway.submit(draft(images: [file])),
        throwsA(isA<SupportInquiryException>()),
      );
    }
    expect(requests, isEmpty);
  });

  test('client limits match the form and DB', () async {
    await expectLater(
      gateway.submit(draft(content: '가' * 1001)),
      throwsA(isA<SupportInquiryException>()),
    );
    await expectLater(
      gateway.submit(draft(images: List.generate(6, (_) => png()))),
      throwsA(isA<SupportInquiryException>()),
    );
    expect(requests, isEmpty);
  });

  test('server rate limit produces a readable retry message', () async {
    rpcFails = rateLimited = true;
    await expectLater(
      gateway.submit(draft()),
      throwsA(
        isA<SupportInquiryException>().having(
          (e) => e.message,
          'message',
          contains('잠시 후'),
        ),
      ),
    );
  });

  test('signed out submission cannot upload or submit', () async {
    await client.auth.signOut(scope: SignOutScope.local);
    requests.clear();
    await expectLater(
      gateway.submit(draft()),
      throwsA(isA<SupportInquiryException>()),
    );
    expect(requests, isEmpty);
  });
}
